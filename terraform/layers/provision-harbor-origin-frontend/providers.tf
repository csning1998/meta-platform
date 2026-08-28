
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
    harbor = {
      source  = "goharbor/harbor"
      version = "3.10.1"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-harbor-origin-frontend"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-harbor-origin-frontend/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-harbor-origin-frontend/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}


# Production Provider (security-vault-approle)
provider "vault" {
  alias        = "production"
  address      = local.sys_vault_endpoint
  ca_cert_file = local.state.security_pki.bastion_pki_chain_b64.path

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = data.terraform_remote_state.security_vault_approle.outputs.role_id
      secret_id = data.terraform_remote_state.security_vault_approle.outputs.secret_id
    }
  }
  skip_child_token = true
}

provider "harbor" {
  url      = "https://${data.terraform_remote_state.harbor_origin.outputs.harbor_origin_fqdn}"
  username = "admin"
  password = ephemeral.vault_kv_secret_v2.harbor_origin.data["harbor_origin_admin_password"]
}
