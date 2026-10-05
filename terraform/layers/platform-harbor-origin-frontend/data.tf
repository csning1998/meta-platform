
data "terraform_remote_state" "foundation_libvirt_resources" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "platform_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-spire-parent-frontend" }
}

data "terraform_remote_state" "security_vault_downstream_pki" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-pki" }
}

data "terraform_remote_state" "security_vault_downstream_tenants" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-vault-downstream-tenants" }
}

data "terraform_remote_state" "provision_spire_child" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-spire-child" }
}
