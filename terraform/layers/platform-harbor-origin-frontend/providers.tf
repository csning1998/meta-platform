
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
    http = {
      source  = "hashicorp/http"
      version = "3.6.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.4.1"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-harbor-origin-frontend"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-harbor-origin-frontend/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/platform-harbor-origin-frontend/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "libvirt" {
  uri = "qemu:///system?socket=/var/run/libvirt/virtqemud-sock"
}

# Authenticated as the local Terraform operator of this component through SPIRE JWT-SVID.
provider "vault" {
  alias        = "downstream"
  address      = local.state.security_vault_downstream_tenants.endpoint
  ca_cert_file = local.state.security_vault_downstream_tenants.ca_cert_path

  auth_login {
    path = "auth/${local.state.security_vault_downstream_tenants.tenant_operator.auth_mount}/login"
    parameters = {
      role = local.state.security_vault_downstream_tenants.tenant_operator.role_name
      jwt  = data.external.spire_jwt_downstream.result.jwt
    }
  }
  skip_child_token = true
}
