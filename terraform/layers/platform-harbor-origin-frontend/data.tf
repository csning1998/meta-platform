
data "terraform_remote_state" "network" {
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

data "vault_generic_secret" "guest_vm" {
  path = "secret/${local.vault_kv_namespace}/guest_vm"
}

data "vault_generic_secret" "harbor_origin" {
  path = "secret/${local.vault_kv_namespace}/harbor-origin/frontend"
}
