

data "terraform_remote_state" "volume" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "cilium" {
  backend = "http"
  config  = { address = "${local._state_base}/platform-cilium-frontend" }
}

data "terraform_remote_state" "security_vault_approle" {
  backend = "http"
  config  = { address = "${local._state_base}/security-vault-approle" }
}

data "terraform_remote_state" "security_pki" {
  backend = "http"
  config  = { address = "${local._state_base}/security-pki" }
}

data "vault_kv_secret_v2" "guest_vm" {
  provider = vault.production
  mount    = "secret"
  name     = "meta-platform/guest_vm"
}

data "vault_kv_secret_v2" "creds" {
  provider = vault.production
  mount    = "secret"
  name     = local.credential_paths["keycloak"]["frontend"]
}
