
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
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-spire-child"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-spire-child/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-spire-child/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "libvirt" {
  uri = "qemu:///system?socket=/var/run/libvirt/virtqemud-sock"
}

provider "vault" {
  alias        = "downstream"
  address      = local.state.security_vault_downstream_tenants.endpoint
  ca_cert_file = local.state.security_vault_downstream_tenants.ca_cert_path

  # The JWT-SVID arrives through TERRAFORM_VAULT_AUTH_JWT from tools/terraform-operator.sh and stays out of the state.
  auth_login_jwt {
    mount = local.downstream_operator.auth_mount
    role  = local.downstream_operator.role_name
  }
  skip_child_token = true
}
