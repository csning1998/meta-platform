
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
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-approle"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-approle/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-approle/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "vault" {
  alias        = "bastion"
  address      = local.state.bootstrapper.vault_dev_endpoint
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

provider "vault" {
  alias        = "production"
  address      = local.production_vault_endpoint
  ca_cert_file = local.state.production.ca_cert_path
  token        = data.vault_kv_secret_v2.bootstrap_credentials.data["prod_vault_root_token"]
}
