
module "service_identity" {
  source  = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version = "0.1.1"

  for_each  = local.state.foundation.foundation_ssh.identity_key_paths
  providers = { vault = vault.bastion }

  vault_credential_context = {
    kv_namespace = local.state.foundation.foundation_vault_path.kv_namespace
    component    = "frontend"
    domain       = split("/", local.state.foundation.foundation_vault_path.ssh_credential_paths[each.key])[1]
    generate     = lookup(local.service_generates, each.key, {})
    static = {
      ssh_private_key_b64 = base64encode(data.local_sensitive_file.ssh_private_key[each.key].content)
      ssh_public_key_b64  = base64encode(data.local_file.ssh_public_key[each.key].content)
    }
  }
}
