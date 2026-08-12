
data "terraform_remote_state" "vault_bootstrapper" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}

data "terraform_remote_state" "vault_production" {
  backend = "http"
  config  = { address = "${local._state_base}/shared-vault-frontend" }
}

data "terraform_remote_state" "vault_prod_bootstrap" {
  backend = "http"
  config  = { address = "${local._state_base}/security-vault-approle" }
}

data "terraform_remote_state" "foundation" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-libvirt-resources" }
}
