
data "terraform_remote_state" "platform_cilium_frontend" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-cilium-frontend" }
}

data "terraform_remote_state" "provision_cilium_frontend" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-cilium-frontend" }
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

# Vault authentication MUST obtain ephemeral JWT-SVID credentials on every execution to prevent state file persistence.
data "external" "spire_jwt" {
  program = ["/usr/local/bin/${local.terraform_operator.wrapper_name}"]
}

ephemeral "vault_kv_secret_v2" "cilium_frontend" {
  mount = "secret"
  name  = local.state.platform_cilium_frontend.foundation_vault_path.kv_paths["cilium"]["frontend"].cluster_config
}
