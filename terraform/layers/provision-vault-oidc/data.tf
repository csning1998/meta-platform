
data "terraform_remote_state" "prod_vault_frontend" {
  backend = "http"
  config  = { address = "${local._state_base}/shared-vault-frontend" }
}

data "terraform_remote_state" "security_vault_approle" {
  backend = "http"
  config  = { address = "${local._state_base}/security-vault-approle" }
}

data "terraform_remote_state" "security_pki" {
  backend = "http"
  config  = { address = "${local._state_base}/security-pki" }
}

data "terraform_remote_state" "keycloak_provisioning" {
  backend = "http"
  config  = { address = "${local._state_base}/provision-keycloak-oidc" }
}

# Read OIDC Client credentials from Vault (Created in provision-*)
data "vault_kv_secret_v2" "keycloak_vault_client" {
  provider = vault.production
  mount    = "secret"
  name     = "${data.terraform_remote_state.security_vault_approle.outputs.vault_kv_namespace}/keycloak/oidc/clients/vault_frontend"
}
