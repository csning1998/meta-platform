
data "terraform_remote_state" "vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base_parent_group_governance}/foundation-vault-bastion" }
}

data "terraform_remote_state" "vault_downstream" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-vault-frontend" }
}

data "terraform_remote_state" "security_vault_downstream_approle" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-vault-approle" }
}

data "terraform_remote_state" "foundation" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/foundation-libvirt-resources" }
}
