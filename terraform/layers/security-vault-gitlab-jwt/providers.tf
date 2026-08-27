
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-gitlab-jwt"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-gitlab-jwt/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/security-vault-gitlab-jwt/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "vault" {
  alias        = "bastion"
  address      = local.state.vault_bastion.bastion_vault_endpoint
  ca_cert_file = abspath("${path.root}/../../../vault/tls/ca.pem")

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = local.state.vault_bastion.role_id
      secret_id = local.state.vault_bastion.secret_id
    }
  }
  skip_child_token = true
}
