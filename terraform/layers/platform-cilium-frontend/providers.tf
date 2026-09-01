
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.0.2"
    }
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
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-cilium-frontend"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-cilium-frontend/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-cilium-frontend/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "libvirt" {
  uri = "qemu:///system?socket=/var/run/libvirt/virtqemud-sock"
}

provider "vault" {
  address      = local.state.vault_bootstrap.bastion_vault_endpoint
  ca_cert_file = abspath("${path.root}/../../../vault/tls/ca.pem")

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = local.state.vault_bootstrap.role_id
      secret_id = local.state.vault_bootstrap.secret_id
    }
  }
  skip_child_token = true
}
