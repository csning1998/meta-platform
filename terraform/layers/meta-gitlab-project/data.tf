
ephemeral "vault_kv_secret_v2" "state_backend" {
  mount = "secret"
  name  = "meta-platform-credentials/state-backend"
}

data "vault_kv_secret_v2" "claude_keys" {
  mount = "secret"
  name  = "meta-platform-credentials/review-bot-api-keys/claude"
}

data "terraform_remote_state" "foundation_group" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base}/group-foundation" })
}
