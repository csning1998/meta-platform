
locals {
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
  _state_auth                         = module.contexts_local_credential._state_auth_gitlab_saas
}

ephemeral "vault_kv_secret_v2" "state_backend" {
  mount = "secret"
  name  = "parent-group-governance/state-backend"
}

data "vault_kv_secret_v2" "claude_keys" {
  mount = "secret"
  name  = "parent-group-governance/review-bot-api-keys/claude"
}

data "terraform_remote_state" "group_topology" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base_parent_group_governance}/group-topology" })
}
