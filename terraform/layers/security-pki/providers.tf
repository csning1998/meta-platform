
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-pki"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-pki/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-pki/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "vault" {
  alias        = "bootstrap"
  address      = local.state.bootstrapper.bastion_vault_endpoint
  ca_cert_file = abspath("${path.root}/../../../vault/tls/ca.pem")

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = local.state.bootstrapper.role_id
      secret_id = local.state.bootstrapper.secret_id
    }
  }
  skip_child_token = true
}

# Production Provider (security-vault-approle): scoped production_admin AppRole, not the
# root-token-backed provider security-vault-approle uses for its own bootstrap operations.
provider "vault" {
  alias        = "production"
  address      = local.prod_vault_endpoint
  ca_cert_file = local.state.production.ca_cert_path

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = local.state.security_vault_approle.role_id
      secret_id = local.state.security_vault_approle.secret_id
    }
  }
  skip_child_token = true
}
