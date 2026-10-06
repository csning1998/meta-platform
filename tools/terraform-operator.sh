#!/usr/bin/env bash
# Runs terraform in a JWT-SVID layer, for example from the layer directory: ../../../tools/terraform-operator.sh apply
# The JWT reaches the Vault provider through TERRAFORM_VAULT_AUTH_JWT and never enters a plan or the state.
set -euo pipefail

layer="$(basename "$PWD")"

# The Vault role of each operator binds one SPIFFE ID, hence a wrong mapping fails the login.
case "$layer" in
  platform-cilium-hubble | provision-cilium-hubble)
    operator="cilium-hubble" ;;
  platform-harbor-origin-frontend | provision-harbor-origin-frontend | provision-harbor-origin-oidc)
    operator="harbor-origin-frontend" ;;
  platform-keycloak-frontend | provision-keycloak-oidc)
    operator="keycloak-frontend" ;;
  platform-spire-child | provision-spire-child)
    operator="spire-child" ;;
  provision-vault-oidc | security-vault-downstream-credentials | security-vault-downstream-pki)
    operator="vault-downstream-frontend" ;;
  *)
    echo "terraform-operator: layer $layer does not log in with a JWT-SVID, run terraform directly" >&2
    exit 64 ;;
esac

wrapper="/usr/local/bin/spire-fetch-meta-platform-terraform-operator-$operator"
[ -x "$wrapper" ] || { echo "terraform-operator: $wrapper is missing, apply provision-spire-parent first" >&2; exit 1; }

TERRAFORM_VAULT_AUTH_JWT="$("$wrapper" | jq -er .jwt)"
export TERRAFORM_VAULT_AUTH_JWT

exec terraform "$@"
