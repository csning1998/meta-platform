
data "terraform_remote_state" "metadata" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base_parent_group_governance}/foundation-vault-bastion" }
}

data "vault_generic_secret" "guest_vm" {
  path = "secret/meta-platform/guest_vm"
}
