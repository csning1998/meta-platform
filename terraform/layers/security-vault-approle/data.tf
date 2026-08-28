
data "terraform_remote_state" "vault_bootstrapper" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}

data "terraform_remote_state" "vault_production" {
  backend = "http"
  config  = { address = "${local._state_base}/platform-vault-frontend" }
}

data "terraform_remote_state" "foundation" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-libvirt-resources" }
}

data "vault_kv_secret_v2" "bootstrap_credentials" {
  provider = vault.bastion
  mount    = "secret"
  name     = "meta-platform/credentials"
}
