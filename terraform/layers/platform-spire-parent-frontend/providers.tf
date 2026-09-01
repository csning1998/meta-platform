
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

# Default for Bootstrap, connect to Local Podman Vault
provider "vault" {
  address      = data.terraform_remote_state.vault_bastion.outputs.bastion_vault_endpoint
  ca_cert_file = abspath("${path.root}/../../../vault/tls/ca.pem")

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = data.terraform_remote_state.vault_bastion.outputs.role_id
      secret_id = data.terraform_remote_state.vault_bastion.outputs.secret_id
    }
  }
  skip_child_token = true
}
