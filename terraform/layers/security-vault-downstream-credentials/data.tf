
data "terraform_remote_state" "security_vault_downstream_tenants" {
  backend = "http"
  config  = { address = "${local._state_base}/security-vault-downstream-tenants" }
}

data "terraform_remote_state" "provision_spire_child" {
  backend = "http"
  config  = { address = "${local._state_base}/provision-spire-child" }
}

data "terraform_remote_state" "foundation_vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base_parent_group_governance}/foundation-vault-bastion" }
}

data "terraform_remote_state" "platform_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base}/platform-spire-parent-frontend" }
}

data "terraform_remote_state" "provision_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base}/provision-spire-parent-frontend" }
}

# The Bastion Vault mints the guest VM credential. The Downstream Vault holds a copy for the layers which run in the Downstream scope.
ephemeral "vault_kv_secret_v2" "guest_vm_bastion" {
  provider = vault.bastion
  mount    = "secret"
  name     = local.guest_vm_kv
}

# The Bastion Vault trusts the SPIRE Parent. The operator logs in with a JWT-SVID which the Parent issued.
data "external" "spire_jwt_bastion" {
  program = ["/usr/local/bin/${local.terraform_operator.wrapper_name}"]
}

# The downstream Vault trusts the SPIRE Child only, and so the operator logs in with a JWT-SVID which the Child issued.
data "external" "spire_jwt_downstream" {
  program = ["/usr/local/bin/${local.state.provision_spire_child.terraform_operator_downstream["vault-downstream"].wrapper_name}"]
}
