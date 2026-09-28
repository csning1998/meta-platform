
data "terraform_remote_state" "metadata" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base_parent_group_governance}/foundation-vault-bastion" }
}

data "terraform_remote_state" "cilium" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-cilium-frontend" }
}

data "vault_kv_secret_v2" "guest_vm" {
  provider = vault.bastion
  mount    = "secret"
  name     = "meta-platform/guest_vm"
}
