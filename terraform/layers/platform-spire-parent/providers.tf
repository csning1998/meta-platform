
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
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-spire-parent-frontend"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-spire-parent-frontend/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-spire-parent-frontend/lock"
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

# Default for Bootstrap, connect to Local Podman Vault
provider "vault" {
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
