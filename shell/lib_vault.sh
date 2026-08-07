#!/bin/bash

# Prevent multiple loading
if [[ -n "${VAULT_SH_LOADED:-}" ]]; then
  (return 0 2>/dev/null) && return 0 || exit 0
fi
readonly VAULT_SH_LOADED=true

# Bastion Vault Variables
readonly BASTION_VAULT_ADDR="https://127.0.0.1:8200"
readonly BASTION_CA="/opt/vault/tls/ca.pem"
readonly BASTION_KEYS_DIR="${SCRIPT_DIR}/vault/keys"
readonly BASTION_TLS_DIR="${SCRIPT_DIR}/vault/tls"
readonly BASTION_INIT_FILE="${BASTION_KEYS_DIR}/init-output.json"
readonly BASTION_UNSEAL_KEY_FILE="${BASTION_KEYS_DIR}/unseal.key"
readonly BASTION_ROOT_TOKEN_FILE="$HOME/.vault-token"
readonly BASTION_VAULT_CONTAINER="meta-platform-vault-bastion"

# Production Vault Variables
readonly PROD_VAULT_ADDR=""
readonly PROD_CA_CERT="${TERRAFORM_DIR}/layers/shared-vault-frontend/tls/bootstrap-ca.crt"

vault_context_handler() {
  local target="$1"

  unset VAULT_ADDR VAULT_TOKEN VAULT_CACERT

  if [[ "$target" == "prod" ]]; then
    log_print "INFO" "[Vault Context] Switching to PRODUCTION (shared-vault-frontend)..."

    export VAULT_ADDR="$PROD_VAULT_ADDR"
    export VAULT_CACERT="$PROD_CA_CERT"

    # Fetch Prod Token from Bastion Vault (Bootstrap)
    if [[ -f "$BASTION_ROOT_TOKEN_FILE" ]]; then
      local bastion_token
      bastion_token=$(cat "$BASTION_ROOT_TOKEN_FILE")

      local response
      response=$(curl -s --cacert "${BASTION_TLS_DIR}/ca.pem" --header "X-Vault-Token: ${bastion_token}" \
        "${BASTION_VAULT_ADDR}/v1/secret/data/meta-platform/credentials")

      local prod_token
      prod_token=$(echo "$response" | jq -r '.data.data.prod_vault_root_token // empty')

      if [[ -n "$prod_token" ]]; then
        export VAULT_TOKEN="$prod_token"
        log_print "INFO" "    - Prod Token retrieved from Bootstrap Vault."
      else
        log_print "WARN" "Connected to Bootstrap Vault, but 'prod_vault_root_token' was not found."
      fi
    else
      log_print "WARN" "Bootstrap Vault Token not found. Cannot retrieve Prod Credentials."
    fi

  else
    log_print "INFO" "[Vault Context] Switching to DEVELOPMENT (Layer <20 / Packer)..."

    local bastion_token
    bastion_token=$(cat "$BASTION_ROOT_TOKEN_FILE" 2>/dev/null)

    export VAULT_ADDR="$BASTION_VAULT_ADDR"
    export VAULT_TOKEN="$bastion_token"
    export VAULT_CACERT="${BASTION_TLS_DIR}/ca.pem"
  fi

  log_print "INFO" "    - VAULT_ADDR: $VAULT_ADDR"
}

# Status Reporting
vault_status_reporter() {
  # Auto-sync token whenever status is reported
  vault_token_sync_handler > /dev/null 2>&1 || true

  log_divider

  if podman exec -i "${BASTION_VAULT_CONTAINER}" vault status -address="${BASTION_VAULT_ADDR}" -ca-cert="${BASTION_CA}" -format=json > /dev/null 2>&1; then
    local status_json
    status_json=$(podman exec -i "${BASTION_VAULT_CONTAINER}" vault status -address="${BASTION_VAULT_ADDR}" -ca-cert="${BASTION_CA}" -format=json)
    local sealed
    sealed=$(echo "$status_json" | jq .sealed 2>/dev/null)
    if [[ "$sealed" == "true" ]]; then
      log_print "WARN" "Bastion Vault: Running (Sealed)"
    else
      log_print "OK" "Bastion Vault: Running (Unsealed)"
    fi
  else
    if podman ps --filter "name=${BASTION_VAULT_CONTAINER}" --filter "status=running" | grep -q "${BASTION_VAULT_CONTAINER}"; then
      log_print "WARN" "Bastion Vault: Running (Not Initialized)"
    else
      log_print "ERROR" "Bastion Vault: Stopped"
    fi
  fi

  # Check Production Vault on Production Guest VM
  if [[ ! -f "$PROD_CA_CERT" ]]; then
    log_print "WARN" "Production Vault: Unknown (CA Cert missing at $PROD_CA_CERT)"
    log_print "INFO" "Run shared-vault-frontend Terraform to generate the Bootstrap CA file."
  else
    # Exit code 0 for Unsealed; 2 for Sealed; 1 for Error
    if timeout 2 vault status -address="${PROD_VAULT_ADDR}" -ca-cert="${PROD_CA_CERT}" -format=json >/dev/null 2>&1; then
      log_print "OK" "Production Vault: Running (Unsealed)"
    elif [[ $? -eq 2 ]]; then
      log_print "WARN" "Production Vault: Running (Sealed)"
    else
      log_print "ERROR" "Production Vault: Stopped or Unreachable"
    fi
  fi

  log_divider
}

# Function: Generate TLS Certs for Bastion Vault (Host)
vault_bastion_tls_generator() {

  log_print "STEP" "[Bastion Vault] Generating CA Root files for TLS..."
  log_print "WARN" "#############################################################################"
  log_print "WARN" "### Proceeding will DESTROY ALL existing files in vault/tls.              ###"
  log_print "WARN" "#############################################################################"

  log_print "INPUT" "Type 'yes' to confirm: "
  read -r confirmation

  if [[ "$confirmation" != "yes" ]]; then
    log_print "INFO" "Cancelled."
    return 1
  fi

  rm -rf "${BASTION_TLS_DIR}"
  mkdir -p "${BASTION_TLS_DIR}"

  # Generates CA and server certificates via host OpenSSL binaries.
  run_command "openssl genrsa -out vault/tls/ca-key.pem 2048" || return 1
  run_command "openssl req -new -x509 -days 365 -key vault/tls/ca-key.pem -sha256 -out vault/tls/ca.pem -subj '/CN=MetaProvisionVaultCA'" || return 1

  run_command "openssl genrsa -out vault/tls/vault-key.pem 2048" || return 1
  run_command "openssl req -subj '/CN=localhost' -sha256 -new -key vault/tls/vault-key.pem -out vault/tls/vault.csr" || return 1

  echo "subjectAltName = DNS:localhost,IP:127.0.0.1" > "${BASTION_TLS_DIR}/extfile.cnf"

	run_command "openssl x509 -req -days 365 -sha256 -in vault/tls/vault.csr \
    -CA vault/tls/ca.pem -CAkey vault/tls/ca-key.pem \
    -CAcreateserial -out vault/tls/vault.pem \
    -extfile vault/tls/extfile.cnf" || return 1

  rm -f "${BASTION_TLS_DIR}/vault.csr" "${BASTION_TLS_DIR}/extfile.cnf"
  chmod 600 "${BASTION_TLS_DIR}/"*key.pem
  chmod 644 "${BASTION_TLS_DIR}/"*.pem

  log_print "OK" "Bastion Vault TLS Certificates generated."
}

# Function: Sync VAULT_TOKEN to .env from JSON or fallback file
vault_token_sync_handler() {
  local token=""

  if [ -f "$BASTION_INIT_FILE" ]; then
    log_print "TASK" "Syncing VAULT_TOKEN from $BASTION_INIT_FILE..."
    token=$(jq -r '.root_token' "$BASTION_INIT_FILE")
  elif [ -f "$BASTION_ROOT_TOKEN_FILE" ]; then
    log_print "TASK" "Syncing VAULT_TOKEN from $BASTION_ROOT_TOKEN_FILE..."
    token=$(cat "$BASTION_ROOT_TOKEN_FILE")
  else
    log_print "WARN" "No Vault token files found. Skipping sync."
    return 0
  fi

  if [[ -n "$token" && "$token" != "null" ]]; then
    env_var_mutator "VAULT_TOKEN" "${token}"
    # Also set for current session
    export VAULT_TOKEN="${token}"
    # Performs an atomic file write to prevent a world readable permission window prior to applying mode 0600.
    local tmp_token
    tmp_token=$(mktemp "${BASTION_ROOT_TOKEN_FILE}.XXXXXX")
    chmod 600 "$tmp_token"
    echo "$token" > "$tmp_token"
    mv "$tmp_token" "$BASTION_ROOT_TOKEN_FILE"
  else
    log_print "ERROR" "Failed to extract a valid token."
    return 1
  fi
}

# Verifies and enables the KV secrets engine for the local bastion Vault instance.
# Layer 00-vault-kv declares this mount via resource vault_mount.kv.
# Execution of this function provides a manual fallback operation rather than the primary state configuration.
vault_bastion_engine_enforcer() {
  log_print "TASK" "[Bastion Vault] Ensuring KV secrets engine is enabled at 'secret/'..."

  if [ ! -f "$BASTION_ROOT_TOKEN_FILE" ]; then
    log_print "ERROR" "Root token not found. Cannot configure engine."
    return 1
  fi

  local root_token
  root_token=$(cat "$BASTION_ROOT_TOKEN_FILE")

  if ! podman exec -i -e VAULT_TOKEN="${root_token}" "${BASTION_VAULT_CONTAINER}" vault secrets list -address="${BASTION_VAULT_ADDR}" -ca-cert="${BASTION_CA}" -format=json | jq -e '."secret/"' > /dev/null; then
    log_print "TASK" "'secret/' path not found, enabling kv-v2..."
    podman exec -i -e VAULT_TOKEN="${root_token}" "${BASTION_VAULT_CONTAINER}" vault secrets enable -address="${BASTION_VAULT_ADDR}" -ca-cert="${BASTION_CA}" -path=secret kv-v2
  else
    log_print "INFO" "kv-v2 secrets engine is already enabled."
  fi
}

# Function: Initialize, Unseal, Login, and Configure Bastion Vault
vault_bastion_init_handler() {
  log_print "STEP" "[Bastion Vault] Initializing Local Podman Vault..."

  if [[ -f "$BASTION_INIT_FILE" ]]; then
		log_print "WARN" "Init file exists. Skipping to prevent data loss."
		return 1
  fi

  mkdir -p "$BASTION_KEYS_DIR"

  log_print "TASK" "Initializing..."
  local tmp_init
  tmp_init=$(mktemp "${BASTION_INIT_FILE}.XXXXXX")
	if ! podman exec -i "${BASTION_VAULT_CONTAINER}" vault operator init -address="${BASTION_VAULT_ADDR}" -ca-cert="${BASTION_CA}" -format=json > "$tmp_init"; then
    rm -f "$tmp_init"
    log_print "FATAL" "Initialization failed. Is ${BASTION_VAULT_CONTAINER} running?"
    return 1
  fi
  mv "$tmp_init" "$BASTION_INIT_FILE"

  # Extract Keys
  local tmp_unseal
  tmp_unseal=$(mktemp "${BASTION_UNSEAL_KEY_FILE}.XXXXXX")
  chmod 600 "$tmp_unseal"
  if ! jq -r '.unseal_keys_b64[]' "$BASTION_INIT_FILE" > "$tmp_unseal"; then
    rm -f "$tmp_unseal"
    log_print "FATAL" "Failed to extract unseal keys from $BASTION_INIT_FILE"
    return 1
  fi
  if [[ ! -s "$tmp_unseal" ]]; then
    rm -f "$tmp_unseal"
    log_print "FATAL" "Unseal key file is empty"
    return 1
  fi
  mv "$tmp_unseal" "$BASTION_UNSEAL_KEY_FILE"
  chmod 600 "$BASTION_KEYS_DIR"/*

  log_print "INFO" "Keys saved to ${BASTION_KEYS_DIR}"

  # Synchronizes root token to .env and home directory fallback paths.
  vault_token_sync_handler

  # Auto Unseal
  if ! vault_bastion_unseal_handler; then
    log_print "ERROR" "Auto-unseal failed. Please unseal manually before configuring engine."
    return 1
  fi

  log_print "OK" "Bastion Vault is ready for use."
}

# Function: Unseal Bastion Vault
vault_bastion_unseal_handler() {
  log_print "STEP" "[Bastion Vault] Unsealing..."

  if [ ! -f "$BASTION_UNSEAL_KEY_FILE" ]; then
    log_print "ERROR" "Unseal keys not found. Run '[BASTION] Initialize' first."
    return 1
  fi

  local status_json
  status_json=$(podman exec -i "${BASTION_VAULT_CONTAINER}" vault status -address="${BASTION_VAULT_ADDR}" -ca-cert="${BASTION_CA}" -format=json 2>/dev/null || true)
  if [[ $(echo "$status_json" | jq .sealed 2>/dev/null) == "false" ]]; then
    log_print "INFO" "Bastion Vault is already unsealed."
    return 0
  fi

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    # Strip carriage returns and pass key as a positional argument, not stdin
    clean_key=$(printf "%s" "$key" | tr -d '\r')
    podman exec "${BASTION_VAULT_CONTAINER}" vault operator unseal -address="${BASTION_VAULT_ADDR}" -ca-cert="${BASTION_CA}" "${clean_key}" || return 1
  done < "$BASTION_UNSEAL_KEY_FILE"

  # Wait for Unseal to propagate
  local timeout=10
  local count=0
  while [ $count -lt $timeout ]; do
    status_json=$(podman exec -i "${BASTION_VAULT_CONTAINER}" vault status -address="${BASTION_VAULT_ADDR}" -ca-cert="${BASTION_CA}" -format=json 2>/dev/null || true)
    if [[ $(echo "$status_json" | jq .sealed 2>/dev/null) == "false" ]]; then
      log_print "OK" "Bastion Vault Unsealed and ready."

      # Export and Sync
      if [ -f "$BASTION_ROOT_TOKEN_FILE" ]; then
        vault_token_sync_handler
        log_print "INFO" "Vault environment variables set for this session."
      fi
      return 0
    fi
    sleep 0.5
    ((count++))
  done

  log_print "ERROR" "Vault sent unseal keys but is still reporting as SEALED after 5 seconds."
  return 1
}

# Function: Trigger Ansible to unseal the production Vault (shared-vault-frontend).
vault_prod_unseal_trigger() {
  log_print "STEP" "[Production Vault] Triggering Ansible Playbook for Unseal..."

  local inventory_file="${ANSIBLE_DIR}/inventory-core-vault-frontend.yaml"
  local playbook_file="${ANSIBLE_DIR}/playbooks/operation_playbook.yaml"

  if [[ ! -f "$inventory_file" ]]; then
    log_print "ERROR" "Inventory file not found at: $inventory_file"
    log_print "INFO" "This file is generated by the shared-vault-frontend Terraform layer on apply."
    return 1
  fi

  if [[ ! -f "$playbook_file" ]]; then
    log_print "ERROR" "Playbook file not found at: $playbook_file"
    return 1
  fi

  if [[ ! -f "${BASTION_ROOT_TOKEN_FILE}" ]]; then
    log_print "ERROR" "Bootstrap Vault Root Token not found at: ${BASTION_ROOT_TOKEN_FILE}"
    log_print "INFO" "Please ensure Dev/Bootstrap Vault is initialized."
    return 1
  fi

  if [[ ! -f "${PROD_CA_CERT}" ]]; then
    log_print "ERROR" "Production Vault CA Cert not found at: ${PROD_CA_CERT}"
    log_print "INFO" "Please ensure Terraform shared-vault-frontend has been applied."
    return 1
  fi

  local prod_ca_b64
  prod_ca_b64=$(base64 "$PROD_CA_CERT" | tr -d '\n')

  if ansible-playbook \
    -i "$inventory_file" \
    "$playbook_file" \
    --tags vault-unseal \
    --extra-vars "dev_vault_url=${BASTION_VAULT_ADDR}" \
    --extra-vars "dev_root_token_path=${BASTION_ROOT_TOKEN_FILE}" \
    --extra-vars "vault_ca_cert_b64=${prod_ca_b64}"; then

    log_print "OK" "[Prod Vault] Unseal Playbook execution completed."
  else
    log_print "ERROR" "[Prod Vault] Unseal Playbook failed."
    return 1
  fi
}
