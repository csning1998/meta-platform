#!/usr/bin/env bash
# Source this file, then select a cluster:
#   platform_cluster cilium | spire-child | vault | keycloak | harbor-origin | <service>/<component>
# To inspect cluster status:
#   platform_cluster_status [cilium | spire-child | vault | keycloak | harbor-origin | all]
# The function exports KUBECONFIG, TALOSCONFIG, and PLATFORM_CLUSTER for the current shell (bash and zsh).
# Credentials come from the Bastion Vault leaf secret/<namespace>/<service>/<component>/cluster-config, which the platform layer of the cluster writes.

platform_cluster() {
  local target env_file addr cacert token ns dir json endpoints

  case "${1:-}" in
    cilium)                 target="cilium/hubble" ;;
    spire-child|spire)      target="spire/child" ;;
    vault|vault-downstream) target="vault-downstream/frontend" ;;
    keycloak)               target="keycloak/frontend" ;;
    harbor|harbor-origin)   target="harbor-origin/frontend" ;;
    */*)                    target="$1" ;;
    *)
      echo "usage: platform_cluster cilium | spire-child | vault | keycloak | harbor-origin | <service>/<component>" >&2
      return 2
      ;;
  esac

  env_file="${PLATFORM_ENV_FILE:-}"
  if [ -z "$env_file" ] || [ ! -r "$env_file" ]; then
    local d="$PWD"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
      if [ -r "$d/.env" ] && grep -qE '^BASTION_VAULT_ADDR=' "$d/.env" 2>/dev/null; then
        env_file="$d/.env"
        break
      fi
      d=$(dirname "$d")
    done
  fi
  [ -r "${env_file:-}" ] || { echo "platform_cluster: cannot locate readable .env (run from project subtree or set PLATFORM_ENV_FILE)" >&2; return 1; }

  local bastion_addr bastion_cacert prod_addr token ns
  bastion_addr=$(grep -E '^BASTION_VAULT_ADDR=' "$env_file" | cut -d= -f2- | tr -d '"')
  bastion_cacert=$(grep -E '^BASTION_VAULT_CACERT=' "$env_file" | cut -d= -f2- | tr -d '"')
  prod_addr=$(grep -E '^PROD_VAULT_ADDR=' "$env_file" | cut -d= -f2- | tr -d '"')
  ns="${PLATFORM_KV_NAMESPACE:-meta-platform}"
  token="${VAULT_TOKEN:-$(cat "$HOME/.vault-token" 2>/dev/null)}"
  [ -n "$token" ] || { echo "platform_cluster: no Vault token (set VAULT_TOKEN or log in with the vault CLI)" >&2; return 1; }

  # Downstream clusters persist cluster-config in Downstream Vault; vault-downstream/frontend persists in Bastion Vault.
  if [ "$target" = "vault-downstream/frontend" ]; then
    json=$(curl -sf --cacert "$bastion_cacert" -H "X-Vault-Token: $token" "$bastion_addr/v1/secret/data/$ns/$target/cluster-config" 2>/dev/null) \
      || { echo "platform_cluster: cannot read secret/$ns/$target/cluster-config from Bastion Vault" >&2; return 1; }
  else
    local prod_token
    prod_token=$(curl -sf --cacert "$bastion_cacert" -H "X-Vault-Token: $token" "$bastion_addr/v1/secret/data/$ns/vault-downstream/frontend/init" \
      | python3 -c 'import json, sys; print(json.load(sys.stdin)["data"]["data"].get("prod_vault_root_token", ""))' 2>/dev/null)

    if [ -n "$prod_token" ] && [ -n "$prod_addr" ]; then
      json=$(curl -sf -k -H "X-Vault-Token: $prod_token" "$prod_addr/v1/secret/data/$ns/$target/cluster-config" 2>/dev/null)
    fi

    if [ -z "$json" ]; then
      json=$(curl -sf --cacert "$bastion_cacert" -H "X-Vault-Token: $token" "$bastion_addr/v1/secret/data/$ns/$target/cluster-config" 2>/dev/null)
    fi

    [ -n "$json" ] || { echo "platform_cluster: cannot read secret/$ns/$target/cluster-config from Downstream Vault or Bastion Vault" >&2; return 1; }
  fi

  dir="${XDG_RUNTIME_DIR:-/tmp}/platform-cluster/$(printf '%s' "$target" | tr '/' '-')"
  (umask 077 && mkdir -p "$dir") || return 1
  chmod 700 "$dir"

  printf '%s' "$json" | python3 -c '
import base64, json, sys
d = json.load(sys.stdin)["data"]["data"]
open(sys.argv[1] + "/kubeconfig", "w").write(base64.b64decode(d["content_b64"]).decode())
' "$dir" || return 1
  chmod 600 "$dir/kubeconfig"

  # The node addresses come from the cluster itself, which keeps the endpoints out of any second source.
  endpoints=$(KUBECONFIG="$dir/kubeconfig" kubectl --request-timeout=10s get nodes \
    -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{" "}{end}' 2>/dev/null)

  printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)["data"]["data"]
out, name = sys.argv[1], sys.argv[2]
nodes = sys.argv[3].split()
lines = ["context: " + name, "contexts:", "  " + name + ":"]
if nodes:
    lines.append("    endpoints: [" + ", ".join(nodes) + "]")
    lines.append("    nodes: [" + ", ".join(nodes) + "]")
lines += ["    ca: " + d["talos_ca_certificate_b64"], "    crt: " + d["talos_client_certificate_b64"], "    key: " + d["talos_client_key_b64"]]
open(out + "/talosconfig", "w").write("\n".join(lines) + "\n")
' "$dir" "$(printf '%s' "$target" | tr '/' '-')" "$endpoints" || return 1
  chmod 600 "$dir/talosconfig"

  export KUBECONFIG="$dir/kubeconfig" TALOSCONFIG="$dir/talosconfig" PLATFORM_CLUSTER="$target"
  echo "platform_cluster: $target, nodes: ${endpoints:-unresolved (the API server did not answer)}"
}

platform_cluster_status() {
  local target="${1:-${PLATFORM_CLUSTER:-}}"
  if [ -z "$target" ]; then
    echo "usage: platform_cluster_status [cilium | spire-child | vault | keycloak | harbor-origin | <service>/<component> | all]" >&2
    return 2
  fi

  if [ "$target" = "all" ]; then
    local c
    for c in cilium spire-child vault keycloak harbor-origin; do
      echo "============================================================"
      echo " Cluster: $c"
      echo "============================================================"
      if platform_cluster "$c" 2>/dev/null; then
        echo "--- Nodes ---"
        kubectl get nodes -o wide --request-timeout=5s 2>/dev/null || echo "Unable to reach Kubernetes API server."
        echo ""
        echo "--- Pods ---"
        kubectl get pods -A --request-timeout=5s 2>/dev/null || echo "Unable to query pods."
      else
        echo "Cluster $c is not provisioned or inaccessible."
      fi
      echo ""
    done
    return 0
  fi

  case "$target" in
    cilium|spire-child|spire|vault|vault-downstream|keycloak|harbor|harbor-origin|*/*)
      platform_cluster "$target" || return 1
      ;;
  esac

  echo "=== Cluster Status: $PLATFORM_CLUSTER ==="
  echo "--- Nodes ---"
  kubectl get nodes -o wide --request-timeout=10s 2>/dev/null || echo "Unable to reach Kubernetes API server."
  echo ""
  echo "--- Pods ---"
  kubectl get pods -A --request-timeout=10s 2>/dev/null || echo "Unable to query pods."
}

platform_cluster_clear() {
  [ -n "${PLATFORM_CLUSTER:-}" ] || return 0
  rm -f "${KUBECONFIG:-}" "${TALOSCONFIG:-}"
  unset KUBECONFIG TALOSCONFIG PLATFORM_CLUSTER
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ -n "$1" ]; then
    echo "Warning: platform-cluster.sh MUST be sourced to export variables to your current shell." >&2
    echo "Please run: source $0 && platform_cluster $1" >&2
  else
    echo "Please run: source $0 && platform_cluster <cluster_name>" >&2
  fi
fi
