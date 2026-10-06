
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


# Downstream Provider, authenticated as the local Terraform operator through its SPIRE JWT-SVID
provider "vault" {
  alias        = "downstream"
  address      = local.downstream_vault_endpoint
  ca_cert_file = local.state.security_vault_downstream_tenants.downstream_vault_ca_cert_path

  # The JWT-SVID arrives through TERRAFORM_VAULT_AUTH_JWT from tools/terraform-operator.sh and stays out of the state.
  auth_login_jwt {
    mount = local.harbor_origin_operator.auth_mount
    role  = local.harbor_origin_operator.role_name
  }
  skip_child_token = true
}

provider "harbor" {
  url      = "https://${local.state.platform_harbor_origin_frontend.harbor_endpoint.fqdn}"
  username = "admin"
  password = ephemeral.vault_kv_secret_v2.harbor_origin.data["harbor_origin_admin_password"]
}
