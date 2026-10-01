
data "terraform_remote_state" "platform_vault_downstream_frontend" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-vault-frontend" }
}

data "terraform_remote_state" "security_vault_downstream_tenants" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-vault-downstream-tenants" }
}

data "terraform_remote_state" "security_vault_downstream_pki" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-pki" }
}

data "terraform_remote_state" "provision_keycloak_oidc" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-keycloak-oidc" }
}

# Read OIDC Client credentials from Vault (Created in provision-*)
data "vault_kv_secret_v2" "keycloak_vault_client" {
  provider = vault.downstream
  mount    = "secret"
  name     = "${local.state.security_vault_downstream_tenants.foundation_vault_path.project_code}/keycloak/oidc/clients/vault_frontend"
}

data "terraform_remote_state" "provision_spire_child" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-spire-child" }
}

# The downstream Vault trusts the SPIRE Child only, and so the operator logs in with a JWT-SVID which the Child issued.
data "external" "spire_jwt_downstream" {
  program = ["/usr/local/bin/${local.state.provision_spire_child.terraform_operator_downstream["vault-downstream"].wrapper_name}"]
}
