
data "terraform_remote_state" "security_vault_downstream_approle" {
  backend = "http"
  config  = { address = "${local._state_base}/security-vault-approle" }
}

data "terraform_remote_state" "security_vault_downstream_pki" {
  backend = "http"
  config  = { address = "${local._state_base}/security-pki" }
}
