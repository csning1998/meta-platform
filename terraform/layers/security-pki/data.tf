
data "terraform_remote_state" "vault_bootstrapper" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}

data "terraform_remote_state" "vault_production" {
  backend = "http"
  config  = { address = "${local._state_base}/platform-vault-frontend" }
}

data "terraform_remote_state" "security_vault_approle" {
  backend = "http"
  config  = { address = "${local._state_base}/security-vault-approle" }
}

data "terraform_remote_state" "foundation" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-libvirt-resources" }
}
