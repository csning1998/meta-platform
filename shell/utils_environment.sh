#!/bin/bash

# Scans project directories to discover Terraform and Packer configuration layers.
iac_layer_discoverer() {
  log_print "STEP" "Discovering Packer Base and Terraform layers..."
  cd "${SCRIPT_DIR}" || return 1

  # Discovers Packer base image layers.
  local packer_layers_str=""
  if [ -d "${PACKER_DIR}" ]; then
    packer_layers_str=$(find "${PACKER_DIR}" -mindepth 2 -maxdepth 2 -name "*.pkrvars.hcl" ! -name "values.pkrvars.hcl" -printf '%f\n' | \
      sed 's/\.pkrvars\.hcl//g' | \
      sort | \
      tr '\n' ' ')
  fi
  env_var_mutator "ALL_PACKER_BASES" "${packer_layers_str% }"

  # Discovers Terraform configuration layers located within terraform/layers.
  local terraform_layers_str=""
  if [ -d "${TERRAFORM_DIR}/layers" ]; then
    terraform_layers_str=$(find "${TERRAFORM_DIR}/layers" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | \
      sort | \
      tr '\n' ' ')
  fi
  env_var_mutator "ALL_TERRAFORM_LAYERS" "${terraform_layers_str% }"

  log_print "INFO" "Layer discovery complete and .env updated."
}

# Locates the production Vault inventory file according to the inventory-*-vault-frontend.yaml naming convention.
# Derives PROD_VAULT_ADDR from the vault_vip key extracted from the target file.
# Resets PROD_VAULT_ADDR to an empty string when zero or multiple files exist or when vault_vip is missing.
prod_vault_inventory_discoverer() {
  local matches
  mapfile -t matches < <(find "${ANSIBLE_DIR}" -maxdepth 1 -name "inventory-*-vault-frontend.yaml" 2>/dev/null)

  if [[ ${#matches[@]} -gt 1 ]]; then
    log_print "ERROR" "Multiple production Vault inventory files found, expected at most one: ${matches[*]}"
    return 1
  fi

  local inventory_file="${matches[0]:-}"
  env_var_mutator "PROD_VAULT_INVENTORY_FILE" "${inventory_file}"

  local vault_vip=""
  if [[ -n "$inventory_file" ]]; then
    vault_vip=$(awk -F'"' '$2 == "vault_vip" {print $4; exit}' "$inventory_file" 2>/dev/null)
  fi

  if [[ -n "$vault_vip" ]]; then
    env_var_mutator "PROD_VAULT_ADDR" "https://${vault_vip}:443"
  else
    env_var_mutator "PROD_VAULT_ADDR" ""
  fi
}

# Function: Check the host operating system family.
host_os_detail_handler() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == *"fedora"* || "$ID" == "fedora" || "$ID" == "rhel" || "$ID" == "centos" ]]; then
      export HOST_OS_FAMILY="rhel"
    elif [[ "$ID" == *"debian"* || "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
      export HOST_OS_FAMILY="debian"
    else
      export HOST_OS_FAMILY="unknown"
    fi
    export HOST_OS_VERSION_ID="${VERSION_ID%%.*}"
  else
    export HOST_OS_FAMILY="unknown"
    export HOST_OS_VERSION_ID="unknown"
  fi
}

# Function: Check for CPU hardware virtualization support (VT-x or AMD-V).
cpu_virt_support_checker() {
  if grep -E -q '^(vmx|svm)' /proc/cpuinfo; then
    export VIRT_SUPPORTED="true"
  else
    export VIRT_SUPPORTED="false"
  fi
}

# Function: Configure Packer network settings based on the guest-VM provisioning strategy.
packer_net_configurator() {
  local strategy="${1:-$ENVIRONMENT_STRATEGY}"
  local bridge_val=""
  local device_val="virtio-net"

  if [[ "$strategy" == "container" ]]; then
    log_print "WARN" "Container strategy detected. Forcing User Mode Networking (SLIRP) for Packer."
    bridge_val=""
  elif ip link show virbr0 >/dev/null 2>&1; then
    bridge_val="virbr0"
    log_print "INFO" "Network Mode: Bridge detected (virbr0). Using performance networking."
  else
    log_print "WARN" "'virbr0' bridge not found. Defaulting to user-mode/SLIRP networking."
    bridge_val=""
  fi

  env_var_mutator "PKR_VAR_NET_BRIDGE" "${bridge_val}"
  env_var_mutator "PKR_VAR_NET_DEVICE" "${device_val}"
}

env_file_bootstrapper() {
  local detected_root="$1"
  local env_path="${detected_root}/.env"

  local current_uid=$(id -u)
  local current_gid=$(id -g)
  local current_uname=$(whoami)

  local current_libvirt_gid
  if getent group libvirt > /dev/null 2>&1; then
    current_libvirt_gid=$(getent group libvirt | cut -d: -f3)
  else
    log_print "WARN" "'libvirt' group not found on host. Using default GID 999."
    current_libvirt_gid=999
  fi

  if [[ ! -f "$env_path" ]]; then
    log_print "INFO" "Creating new .env file..."

    cat > "$env_path" <<EOF
# Project Root
PROJECT_ROOT="${detected_root}"

# Core Strategy Selection: "container" or "native", governs guest-VM provisioning only.
ENVIRONMENT_STRATEGY="native"

# Discovered Layers
ALL_PACKER_BASES=""
ALL_TERRAFORM_LAYERS=""
PROD_VAULT_INVENTORY_FILE=""
PROD_VAULT_ADDR=""

# Vault Configuration
DEV_VAULT_ADDR="https://127.0.0.1:8200"
DEV_VAULT_CACERT="\${PROJECT_ROOT}/vault/tls/ca.pem"
VAULT_TOKEN=""

# Container Runtime
HOST_UID=${current_uid}
HOST_GID=${current_gid}
UNAME=${current_uname}
UHOME=\${HOME}

# For Unpriviledged Podman
PKR_VAR_NET_BRIDGE=""
PKR_VAR_NET_DEVICE="virtio-net"

# For Podman on Ubuntu/Fedora/RHEL to get the GID of the libvirt group
LIBVIRT_GID=${current_libvirt_gid}
EOF
  else
    # Update critical host info
    env_var_mutator "HOST_UID" "${current_uid}"
    env_var_mutator "HOST_GID" "${current_gid}"
    env_var_mutator "PROJECT_ROOT" "${detected_root}"
    env_var_mutator "LIBVIRT_GID" "${current_libvirt_gid}"

    # Backfill keys introduced after this .env file was first created, without
    # overwriting a value the user may have already switched away from the default.
    if ! grep -q "^ENVIRONMENT_STRATEGY=" "$env_path"; then
      env_var_mutator "ENVIRONMENT_STRATEGY" "native"
    fi
  fi

  iac_layer_discoverer
  prod_vault_inventory_discoverer

  local current_strategy
  current_strategy=$(grep "^ENVIRONMENT_STRATEGY=" "$env_path" | cut -d'=' -f2 | tr -d '"')
  packer_net_configurator "${current_strategy:-native}"
}

# Updates or appends a key value pair within the .env file.
env_var_mutator() {
  local key="$1"
  local value="$2"
  local env_file="${SCRIPT_DIR}/.env"

  local escaped_key
  escaped_key=$(printf '%s' "${key}" | sed 's/[.^$*[\\]/\\&/g')
  local escaped_value
  escaped_value=$(printf '%s' "${value}" | sed 's/[|&\\]/\\&/g')

  if grep -q "^${escaped_key}[[:space:]]*=" "$env_file"; then
    sed -i "s|^\\(${escaped_key}\\s*=\\s*\\).*|\\1\"${escaped_value}\"|" "$env_file"
  else
    echo "${key}=\"${value}\"" >> "$env_file"
  fi
}

# Function to handle the interactive strategy switching, restarting entry.sh under the new value.
switch_strategy() {
  local var_name="$1"
  local new_value="$2"

  env_var_mutator "$var_name" "$new_value"
  log_print "INFO" "Strategy '${var_name}' in .env updated to '${new_value}'."
  cd "${SCRIPT_DIR}" && exec ./entry.sh
}

strategy_switch_handler() {
  echo
  log_print "INFO" "Switching strategy..."
  log_print "INFO" "Cleaning Terraform plugins/cache (keeping state)..."
  (cd "${TERRAFORM_DIR}" && rm -rf .terraform .terraform.lock.hcl)

  log_divider

  local new_strategy
  new_strategy=$([[ "$ENVIRONMENT_STRATEGY" == "container" ]] && echo "native" || echo "container")

  packer_net_configurator "${new_strategy}"
  switch_strategy "ENVIRONMENT_STRATEGY" "$new_strategy"
}
