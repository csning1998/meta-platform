
locals {
  _service_generates = {
    "platform-harbor-origin-frontend" = {
      harbor_origin_admin_password = { length = 32 }
      harbor_origin_pg_db_password = { length = 32 }
    }
  }
}

module "service_identity" {
  for_each   = local.state.metadata.ssh_identity_key_paths
  source     = "../../modules/vault-provisioning/vault-credential"
  providers  = { vault = vault.bastion }
  depends_on = [vault_mount.kv]

  vault_kv_namespace = local.state.metadata.vault_kv_namespace
  domain             = split("/", local.state.metadata.ssh_credential_paths[each.key])[1]
  component          = "frontend"

  static = {
    ssh_private_key_b64 = base64encode(data.local_sensitive_file.ssh_private_key[each.key].content)
    ssh_public_key_b64  = base64encode(data.local_file.ssh_public_key[each.key].content)
  }

  generate = lookup(local._service_generates, each.key, {})
}
