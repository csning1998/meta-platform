
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-vault-oidc"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-vault-oidc/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-vault-oidc/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "vault" {
  alias        = "production"
  address      = local.vault_endpoint
  ca_cert_file = local.state.security_pki.bastion_pki_chain_b64.path

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = local.state.security_vault_approle.role_id
      secret_id = local.state.security_vault_approle.secret_id
    }
  }
  skip_child_token = true
}
