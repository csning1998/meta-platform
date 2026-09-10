
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
    ansible = {
      source  = "ansible/ansible"
      version = "~> 1.5.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-spire-parent-frontend"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-spire-parent-frontend/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-spire-parent-frontend/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

# Provider authentication MUST utilize the VAULT_TOKEN environment variable to prevent sensitive credential persistence
# within Terraform state files. This layer provisions JWT authentication roles required for downstream layer bootstrapping.
provider "vault" {
  address      = local.state.vault_bastion.bastion_vault_endpoint
  ca_cert_file = local.state.vault_bastion.bastion_vault_listener_ca_cert_path
}
