
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

# The tenant session supplies VAULT_ADDR, VAULT_CACERT, and VAULT_TOKEN, hence the layer does not hold any Bastion credential.
# The tenant token cannot create a child token, since the tenant ACL does not grant any auth/token path.
provider "vault" {
  skip_child_token = true
}
