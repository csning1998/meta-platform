
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
    external = {
      source  = "hashicorp/external"
      version = "2.4.1"
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
  ca_cert_file = local.state.vault_bootstrap.bastion_vault_listener_ca_cert_path

  auth_login {
    path = "auth/${local.state.spire_parent.spire_oidc_auth_backend_path}/login"
    parameters = {
      role = local.svc_identity.cluster_name
      jwt  = data.external.spire_jwt.result.jwt
    }
  }
  skip_child_token = true
}
