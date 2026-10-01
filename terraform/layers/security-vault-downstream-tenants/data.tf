
data "terraform_remote_state" "foundation_vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base_parent_group_governance}/foundation-vault-bastion" }
}

data "terraform_remote_state" "foundation_libvirt_resources" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "platform_vault_downstream_frontend" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-vault-frontend" }
}

data "terraform_remote_state" "platform_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-spire-parent-frontend" }
}

data "terraform_remote_state" "provision_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-spire-parent-frontend" }
}

data "terraform_remote_state" "provision_spire_child" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-spire-child" }
}

# Vault authentication MUST obtain ephemeral JWT-SVID credentials on every execution to prevent state file persistence.
data "external" "spire_jwt" {
  program = ["/usr/local/bin/${local.terraform_operator.wrapper_name}"]
}

ephemeral "vault_kv_secret_v2" "downstream_init" {
  provider = vault.bastion

  mount = "secret"
  name  = local.kv_paths.init
}
