
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.4.1"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-downstream-tenants"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-downstream-tenants/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-downstream-tenants/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

# Bastion Vault provider authenticates via SPIRE JWT-SVID solely to retrieve downstream initialization material.
provider "vault" {
  alias        = "bastion"
  address      = local.state.foundation_vault_bastion.bastion_vault.endpoint
  ca_cert_file = local.state.foundation_vault_bastion.bastion_vault.listener_ca_cert_path

  auth_login {
    path = "auth/${local.state.platform_spire_parent.spire_oidc_auth_backend_path}/login"
    parameters = {
      role = local.terraform_operator.role_name
      jwt  = data.external.spire_jwt.result.jwt
    }
  }
  skip_child_token = true
}

# Downstream Vault provider uses ephemeral bootstrap root token to configure initial JWT auth and tenant policies.
provider "vault" {
  alias            = "downstream"
  address          = local.downstream_vault.endpoint
  ca_cert_file     = local.downstream_vault.ca_cert_path
  token            = ephemeral.vault_kv_secret_v2.downstream_init.data["prod_vault_root_token"]
  skip_child_token = true
}
