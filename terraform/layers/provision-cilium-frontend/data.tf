
data "terraform_remote_state" "cilium_frontend" {
  backend = "http"
  config  = { address = "${local._state_base}/platform-cilium-frontend" }
}

data "terraform_remote_state" "vault_bootstrapper" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}

ephemeral "vault_kv_secret_v2" "cilium_frontend" {
  mount = "secret"
  name  = "${local.vault_kv_namespace}/cilium/frontend"
}
