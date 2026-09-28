
module "credential_keycloak_frontend" {
  source  = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version = "0.1.1"

  providers = {
    vault.production = vault.downstream
  }

  vault_credential_context = {
    kv_namespace = local.vault_kv_namespace
    domain       = "keycloak"
    component    = "frontend"
    static = {
      keycloak_admin_user = var.keycloak_admin_user
      keycloak_db_user    = var.keycloak_db_user
    }
    generate = {
      keycloak_admin_password = { length = 32 }
      keycloak_db_password    = { length = 32 }
    }
  }
}

module "credential_harbor_origin_frontend" {
  source  = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version = "0.1.1"

  providers = {
    vault.production = vault.downstream
  }

  vault_credential_context = {
    kv_namespace = local.vault_kv_namespace
    domain       = "harbor-origin"
    component    = "frontend"
    generate = {
      harbor_origin_admin_password = { length = 32 }
      harbor_origin_pg_db_password = { length = 32 }
    }
  }
}
