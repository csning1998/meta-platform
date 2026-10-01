
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

data "terraform_remote_state" "provision_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-spire-parent-frontend" }
}

data "terraform_remote_state" "security_vault_downstream_pki" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-pki" }
}

data "terraform_remote_state" "security_vault_downstream_tenants" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-vault-downstream-tenants" }
}

data "vault_generic_secret" "guest_vm" {
  path = "secret/${local.state.foundation_libvirt_resources.foundation_vault_path.guest_vm_path}"
}

# security-vault-downstream-credentials mints the administrator and database passwords of Harbor.
# The Downstream Vault is the only holder of the passwords.
data "vault_kv_secret_v2" "harbor_origin" {
  provider = vault.downstream

  mount = "secret"
  name  = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["harbor-origin"]["frontend"].app
}

# Vault authentication MUST obtain ephemeral JWT-SVID credentials on every execution to prevent state file persistence.
data "external" "spire_jwt" {
  program = ["/usr/local/bin/${local.terraform_operator.wrapper_name}"]
}

data "terraform_remote_state" "provision_spire_child" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-spire-child" }
}

# The downstream Vault trusts the SPIRE Child only, and so the operator logs in with a JWT-SVID which the Child issued.
data "external" "spire_jwt_downstream" {
  program = ["/usr/local/bin/${local.state.provision_spire_child.terraform_operator_downstream["harbor-origin"].wrapper_name}"]
}
