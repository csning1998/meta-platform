
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
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-downstream-credentials"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-downstream-credentials/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-downstream-credentials/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "vault" {
  alias        = "downstream"
  address      = local.downstream_vault.endpoint
  ca_cert_file = local.downstream_vault.ca_cert_path

  auth_login {
    path = "auth/${local.state.security_vault_downstream_tenants.tenant_operator.auth_mount}/login"
    parameters = {
      role = local.state.security_vault_downstream_tenants.tenant_operator.role_name
      jwt  = data.external.spire_jwt_downstream.result.jwt
    }
  }
  skip_child_token = true
}

# The Bastion Vault is read only. The operator of this component logs in through the JWT-SVID of the SPIRE Parent.
provider "vault" {
  alias        = "bastion"
  address      = local.state.foundation_vault_bastion.bastion_vault.endpoint
  ca_cert_file = local.state.foundation_vault_bastion.bastion_vault.listener_ca_cert_path

  auth_login {
    path = "auth/${local.state.platform_spire_parent.spire_oidc_auth_backend_path}/login"
    parameters = {
      role = local.terraform_operator.role_name
      jwt  = data.external.spire_jwt_bastion.result.jwt
    }
  }
  skip_child_token = true
}
