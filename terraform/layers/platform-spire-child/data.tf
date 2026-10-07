
data "terraform_remote_state" "foundation_libvirt_resources" {
  backend = "http"
  config  = { address = "${local._state_base_platform_foundation}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "security_vault_downstream_tenants" {
  backend = "http"
  config  = { address = "${local._state_base_platform_foundation}/security-vault-downstream-tenants" }
}
