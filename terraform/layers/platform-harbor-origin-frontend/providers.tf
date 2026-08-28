
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.7"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/infra-harbor-origin-frontend"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/infra-harbor-origin-frontend/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/infra-harbor-origin-frontend/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

provider "vault" {
  address      = local.state.vault_bastion.bastion_vault_endpoint
  ca_cert_file = local.state.vault_bastion.bastion_vault_listener_ca_cert_path

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = local.state.vault_bastion.role_id
      secret_id = local.state.vault_bastion.secret_id
    }
  }
  skip_child_token = true
}
