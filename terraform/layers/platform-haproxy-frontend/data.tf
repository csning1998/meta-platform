
data "terraform_remote_state" "network" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}

data "terraform_remote_state" "spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base}/platform-spire-parent-frontend" }
}

data "vault_generic_secret" "guest_vm" {
  path = "secret/${local.vault_kv_namespace}/guest_vm"
}

# Vault authentication MUST obtain ephemeral JWT-SVID credentials on every execution to prevent state file persistence.
data "external" "spire_jwt" {
  program = ["/usr/local/bin/spire-fetch-platform-haproxy-frontend"]
}
