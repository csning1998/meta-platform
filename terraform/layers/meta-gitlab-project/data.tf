
locals {
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
  _state_auth                         = module.contexts_local_credential.state_auth_gitlab_saas

  # Uses read_api CLI credentials for state authentication to prevent higher-privilege token persistence
  # in local terraform_remote_state config blocks.
  _gl_creds = jsondecode(file(pathexpand("~/.terraform.d/credentials.tfrc.json")))

  # Reads Vault token directly from host token-helper file to break cyclic authentication dependencies
  # during initialization.
  vault_token = trimspace(file(pathexpand("~/.vault-token")))
}

ephemeral "vault_kv_secret_v2" "state_backend" {
  provider = vault.bastion
  mount    = "secret"
  name     = "parent-group-governance/terraform/state-backend"
}

ephemeral "vault_kv_secret_v2" "github_publication" {
  provider = vault.bastion
  mount    = "secret"
  name     = "parent-group-governance/github/publication"
}

data "terraform_remote_state" "group_federation_anthropic" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base_parent_group_governance}/group-federation-anthropic" })
}

data "terraform_remote_state" "group_federation_gcp" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base_parent_group_governance}/group-federation-gcp" })
}

data "terraform_remote_state" "group_federation_azure" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base_parent_group_governance}/group-federation-azure" })
}

ephemeral "vault_kv_secret_v2" "anthropic_admin_key" {
  provider = vault.bastion
  mount    = "secret"
  name     = "parent-group-governance/ai-provider-console/anthropic"
}

data "terraform_remote_state" "group_topology" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base_parent_group_governance}/group-topology" })
}
