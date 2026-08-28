
module "keycloak_frontend" {
  source = "../../modules/vault-provisioning/vault-credential"

  domain    = "keycloak"
  component = "frontend"

  static = {
    keycloak_admin_user = var.keycloak_admin_user
    keycloak_db_user    = var.keycloak_db_user
  }

  generate = {
    keycloak_admin_password = { length = 32 }
    keycloak_db_password    = { length = 32 }
  }

  vault_kv_namespace = local.vault_kv_namespace

  providers = {
    vault.production = vault.production
  }
}

module "harbor_origin_frontend" {
  source = "../../modules/vault-provisioning/vault-credential"

  domain    = "harbor-origin"
  component = "frontend"

  generate = {
    harbor_origin_admin_password = { length = 32 }
    harbor_origin_pg_db_password = { length = 32 }
  }

  vault_kv_namespace = local.vault_kv_namespace

  providers = {
    vault.production = vault.production
  }
}
