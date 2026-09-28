
terraform {
  required_providers {
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

module "contexts_local_credential" {
  source  = "gitlab.com/csning1998-lab/contexts-local-credential/gitlab"
  version = "0.1.1"
}

provider "vault" {
  alias        = "bastion"
  address      = local.state.vault_bastion.bastion_vault.endpoint
  ca_cert_file = module.contexts_local_credential.bastion_vault_config.ca_cert_path

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = local.state.vault_bastion.bastion_vault_tenant.terraform_operator.role_ids[local.owner_code]
      secret_id = local.state.vault_bastion.bastion_vault_tenant_credential.terraform_operator.secret_ids[local.owner_code]
    }
  }
  skip_child_token = true
}

# Downstream Provider: scoped production_admin AppRole, not the root-token-backed provider
# security-vault-downstream-approle uses for its own bootstrap operations.
provider "vault" {
  alias        = "downstream"
  address      = local.prod_vault_endpoint
  ca_cert_file = local.state.vault_downstream.ca_cert_path

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = local.state.security_vault_downstream_approle.role_id
      secret_id = local.state.security_vault_downstream_approle.secret_id
    }
  }
  skip_child_token = true
}
