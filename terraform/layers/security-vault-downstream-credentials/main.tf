
module "credential_keycloak_frontend" {
  source  = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version = "0.1.1"

  providers = {
    vault = vault.downstream
  }

  vault_credential_context = {
    kv_namespace = dirname(dirname(local.kv_paths["keycloak"]["frontend"].app))
    domain       = basename(dirname(local.kv_paths["keycloak"]["frontend"].app))
    component    = basename(local.kv_paths["keycloak"]["frontend"].app)
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
    kv_namespace = dirname(dirname(local.kv_paths["harbor-origin"]["frontend"].app))
    domain       = basename(dirname(local.kv_paths["harbor-origin"]["frontend"].app))
    component    = basename(local.kv_paths["harbor-origin"]["frontend"].app)
    generate = {
      harbor_origin_admin_password = { length = 32 }
      harbor_origin_pg_db_password = { length = 32 }
    }
  }
}

resource "vault_kv_secret_v2" "guest_vm_downstream" {
  provider             = vault.downstream
  mount                = "secret"
  name                 = local.guest_vm_kv
  data_json_wo         = jsonencode(ephemeral.vault_kv_secret_v2.guest_vm_bastion.data)
  data_json_wo_version = var.guest_vm_sync_version
}
