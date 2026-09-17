
data "terraform_remote_state" "security_vault_approle" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-vault-approle" }
}

data "terraform_remote_state" "security_pki" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-pki" }
}

data "terraform_remote_state" "keycloak" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-keycloak-frontend" }
}

ephemeral "vault_kv_secret_v2" "keycloak_admin" {
  provider = vault.production
  mount    = "secret"
  name     = local.credential_paths["keycloak"]["frontend"]
}
