
module "credential_keycloak_frontend" {
  source  = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version = "0.1.1"

  providers = {
    vault = vault.downstream
  }

  vault_credential_context = {
    kv_namespace = dirname(dirname(local.downstream_kv_paths["keycloak"]["frontend"].app))
    domain       = basename(dirname(local.downstream_kv_paths["keycloak"]["frontend"].app))
    component    = basename(local.downstream_kv_paths["keycloak"]["frontend"].app)
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
    vault = vault.downstream
  }

  vault_credential_context = {
    kv_namespace = dirname(dirname(local.downstream_kv_paths["harbor-origin"]["frontend"].app))
    domain       = basename(dirname(local.downstream_kv_paths["harbor-origin"]["frontend"].app))
    component    = basename(local.downstream_kv_paths["harbor-origin"]["frontend"].app)
    generate = {
      harbor_origin_admin_password = { length = 32 }
      harbor_origin_pg_db_password = { length = 32 }
    }
  }
}

# The Hubble UI login. External Secrets Operator derives the bcrypt htpasswd line inside the cluster. No hash enters a Terraform state.
module "credential_cilium_hubble_ui" {
  source  = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version = "0.1.1"

  providers = {
    vault = vault.downstream
  }

  vault_credential_context = {
    kv_namespace = dirname(dirname(local.kv_path_cilium_hubble_ui))
    domain       = basename(dirname(local.kv_path_cilium_hubble_ui))
    component    = basename(local.kv_path_cilium_hubble_ui)
    generate = {
      password      = { length = 24 }
      cookie_secret = { length = 32 }
    }
  }
}
