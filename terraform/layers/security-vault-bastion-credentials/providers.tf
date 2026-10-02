
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-bastion-credentials"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-bastion-credentials/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-bastion-credentials/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

module "contexts_local_credential" {
  source  = "gitlab.com/csning1998-lab/contexts-local-credential/gitlab"
  version = "0.3.1"
}

provider "vault" {
  alias        = "bastion"
  address      = local.state.foundation_vault_bastion.bastion_vault.endpoint
  ca_cert_file = module.contexts_local_credential.bastion_vault_config.ca_cert_path

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = local.state.foundation_vault_bastion.bastion_vault_tenant.terraform_operator.role_ids[local.project_code]
      secret_id = local.state.foundation_vault_bastion.bastion_vault_tenant_credential.terraform_operator.secret_ids[local.project_code]
    }
  }
  skip_child_token = true
}
