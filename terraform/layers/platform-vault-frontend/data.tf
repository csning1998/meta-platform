
data "terraform_remote_state" "metadata" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "vault_bootstrapper" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}

data "terraform_remote_state" "load_balancer" {
  backend = "http"
  config  = { address = "${local._state_base}/platform-load-balancer-frontend" }
}

data "vault_kv_secret_v2" "guest_vm" {
  mount = "secret"
  name  = "meta-platform/guest_vm"
}
