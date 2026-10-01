
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
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-pki"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-pki/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-pki/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

# Bastion Vault, authenticated as the SPIRE JWT-SVID operator of the Downstream Vault. The operator policy grants the signing path.
provider "vault" {
  alias        = "bastion"
  address      = local.state.foundation_vault_bastion.bastion_vault.endpoint
  ca_cert_file = local.state.foundation_vault_bastion.bastion_vault.listener_ca_cert_path

  auth_login {
    path = "auth/${local.state.platform_spire_parent.spire_oidc_auth_backend_path}/login"
    parameters = {
      role = local.state.provision_spire_parent.terraform_operator["vault-downstream"].role_name
      jwt  = data.external.spire_jwt_bastion.result.jwt
    }
  }
  skip_child_token = true
}

# Downstream Provider: the local Terraform operator through its SPIRE JWT-SVID, not the root token
# which security-vault-downstream-tenants uses for its own bootstrap operations.
provider "vault" {
  alias        = "downstream"
  address      = local.downstream_vault.endpoint
  ca_cert_file = local.state.platform_vault_downstream_frontend.ca_cert_path

  auth_login {
    path = "auth/${local.state.security_vault_downstream_tenants.tenant_operator.auth_mount}/login"
    parameters = {
      role = local.state.security_vault_downstream_tenants.tenant_operator.role_name
      jwt  = data.external.spire_jwt_downstream.result.jwt
    }
  }
  skip_child_token = true
}
