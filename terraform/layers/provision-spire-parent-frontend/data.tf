
data "terraform_remote_state" "metadata" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}

data "terraform_remote_state" "spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base}/platform-spire-parent-frontend" }
}
