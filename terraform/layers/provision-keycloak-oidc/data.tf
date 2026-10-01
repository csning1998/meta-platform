
data "terraform_remote_state" "security_vault_downstream_tenants" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-vault-downstream-tenants" }
}

data "terraform_remote_state" "security_vault_downstream_pki" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-pki" }
}

data "terraform_remote_state" "platform_keycloak_frontend" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-keycloak-frontend" }
}

ephemeral "vault_kv_secret_v2" "keycloak_admin" {
  provider = vault.downstream
  mount    = "secret"
  name     = local.kv_paths["keycloak"]["frontend"].app
}

data "terraform_remote_state" "provision_spire_child" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-spire-child" }
}

# The downstream Vault trusts the SPIRE Child only, and so the operator logs in with a JWT-SVID which the Child issued.
data "external" "spire_jwt_downstream" {
  program = ["/usr/local/bin/${local.state.provision_spire_child.terraform_operator_downstream["keycloak"].wrapper_name}"]
}
