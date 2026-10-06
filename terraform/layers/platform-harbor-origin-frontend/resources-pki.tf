# The bootstrap leaf comes from the Downstream Vault PKI, whose role security-vault-downstream-pki declares.
# Vault Agent takes over the renewal once the VM runs.
resource "vault_pki_secret_backend_cert" "listener" {
  provider = vault.downstream

  backend     = module.terraform_layer_context.vault_agent_identity_base.pki_mount_path
  name        = module.terraform_layer_context.vault_agent_identity_base.role_name
  common_name = local.state.foundation_libvirt_resources.foundation_pki.map[module.terraform_layer_context.primary_context.pki_key].dns_san[0]
  alt_names   = local.state.foundation_libvirt_resources.foundation_pki.map[module.terraform_layer_context.primary_context.pki_key].dns_san
  ip_sans     = concat(local.harbor_node_ips, [module.terraform_layer_context.primary_network_config.lb_config.vip])

  # Rotate the bootstrap leaf before expiry while Vault Agent is inactive in the bootstrapping stage.
  auto_renew            = true
  min_seconds_remaining = 60 * 60 * 24 * 7 # 7 Days
}
