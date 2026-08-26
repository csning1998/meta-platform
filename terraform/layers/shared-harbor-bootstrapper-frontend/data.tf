
data "terraform_remote_state" "network" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}

data "vault_kv_secret_v2" "guest_vm" {
  mount = "secret"
  name  = "${local.vault_kv_namespace}/guest_vm"
}

data "vault_kv_secret_v2" "harbor_origin" {
  mount = "secret"
  name  = "${local.vault_kv_namespace}/harbor-origin/frontend"
}
