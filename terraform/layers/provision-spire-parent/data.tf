
data "terraform_remote_state" "foundation_libvirt_resources" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "foundation_vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base_parent_group_governance}/foundation-vault-bastion" }
}

data "terraform_remote_state" "platform_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-spire-parent-frontend" }
}
