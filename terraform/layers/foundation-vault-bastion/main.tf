
# The Production Vault is not reachable when Harbor Origin is applied.
module "harbor_origin_credentials" {
  source     = "../../modules/vault-provisioning/vault-credential"
  providers  = { vault = vault.bastion }
  depends_on = [vault_mount.kv]

  vault_kv_namespace = local.state.metadata.vault_kv_namespace
  domain             = "harbor-origin"
  component          = "frontend"

  generate = {
    harbor_origin_admin_password = { length = 32 }
    harbor_origin_pg_db_password = { length = 32 }
  }
}
