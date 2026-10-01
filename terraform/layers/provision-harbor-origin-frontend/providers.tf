
terraform {
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "2.4.1"
    }
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
  address      = local.sys_vault_endpoint
  ca_cert_file = local.state.security_vault_downstream_pki.bastion_pki_chain_b64.path

  auth_login {
    path = "auth/${local.state.security_vault_downstream_tenants.tenant_operator.auth_mount}/login"
    parameters = {
      role = local.state.security_vault_downstream_tenants.tenant_operator.role_name
      jwt  = data.external.spire_jwt_downstream.result.jwt
    }
  }
  skip_child_token = true
}

provider "harbor" {
  url      = "https://${local.state.platform_harbor_origin_frontend.harbor_origin_fqdn}"
  username = "admin"
  password = ephemeral.vault_kv_secret_v2.harbor_origin.data["harbor_origin_admin_password"]
}
