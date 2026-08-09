
data "terraform_remote_state" "vault_bootstrapper" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}

data "terraform_remote_state" "metadata" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-metadata" }
}

data "terraform_remote_state" "network" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-libvirt-resources" }
}

data "vault_kv_secret_v2" "guest_vm" {
  mount = "secret"
  name  = "meta-platform/guest_vm"
}

data "vault_kv_secret_v2" "infrastructure" {
  mount = "secret"
  name  = "meta-platform/infrastructure"
}

data "vault_kv_secret_v2" "credentials" {
  mount = "secret"
  name  = "meta-platform/credentials"
}
