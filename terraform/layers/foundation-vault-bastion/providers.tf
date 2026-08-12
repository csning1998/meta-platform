
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/foundation-vault-bastion"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/foundation-vault-bastion/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/foundation-vault-bastion/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

# The target Vault being configured (Bootstrapper/Initial Vault)
provider "vault" {
  address      = var.bastion_vault_endpoint
  ca_cert_file = abspath("${path.root}/../../../vault/tls/ca.pem")
}
