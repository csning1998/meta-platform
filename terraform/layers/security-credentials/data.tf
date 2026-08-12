
data "terraform_remote_state" "vault_prod_bootstrap" {
  backend = "http"
  config  = { address = "${local._state_base}/security-vault-approle" }
}

data "terraform_remote_state" "vault_pki" {
  backend = "http"
  config  = { address = "${local._state_base}/security-pki" }
}
