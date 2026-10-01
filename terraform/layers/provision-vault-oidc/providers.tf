
terraform {
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "2.4.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-vault-oidc"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-vault-oidc/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-vault-oidc/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "vault" {
  alias        = "downstream"
  address      = local.downstream_vault.endpoint
  ca_cert_file = local.state.security_vault_downstream_pki.bastion_pki_chain_b64.path

  auth_login {
    path = "auth/${local.state.security_vault_downstream_tenants.tenant_operator.auth_mount}/login"
    parameters = {
      role = local.state.security_vault_downstream_tenants.tenant_operator.role_name
      jwt  = data.external.spire_jwt_downstream.result.jwt
    }
  }
  skip_child_token = true
}
