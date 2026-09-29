
terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.7"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.4.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-vault-frontend"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-vault-frontend/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-vault-frontend/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "libvirt" {
  uri = "qemu:///system?socket=/var/run/libvirt/virtqemud-sock"
}

module "contexts_local_credential" {
  source  = "gitlab.com/csning1998-lab/contexts-local-credential/gitlab"
  version = "0.3.0"
}

# Bastion Vault, authenticated as the tenant Terraform operator of meta-platform.
provider "vault" {
  alias        = "bastion"
  address      = data.terraform_remote_state.vault_bastion.outputs.bastion_vault.endpoint
  ca_cert_file = module.contexts_local_credential.bastion_vault_config.ca_cert_path

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = data.terraform_remote_state.vault_bastion.outputs.bastion_vault_tenant.terraform_operator.role_ids[local.owner_code]
      secret_id = data.terraform_remote_state.vault_bastion.outputs.bastion_vault_tenant_credential.terraform_operator.secret_ids[local.owner_code]
    }
  }
  skip_child_token = true
}
