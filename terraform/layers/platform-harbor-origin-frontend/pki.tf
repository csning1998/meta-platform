
# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item D.
resource "vault_pki_secret_backend_cert" "listener" {
  backend     = local.state.vault_bastion.bastion_pki_inter_mount_path
  name        = local.harbor_pki_role_name
  common_name = local.state.network.global_pki_map["harbor-origin-frontend"].dns_san[0]
  alt_names   = local.state.network.global_pki_map["harbor-origin-frontend"].dns_san
  ip_sans     = concat(local.harbor_node_ips, [module.context.primary_net_config.lb_config.vip])

  # Rotate the bootstrap leaf before expiry while Vault Agent is inactive in the bootstrapping stage.
  auto_renew            = true
  min_seconds_remaining = 60 * 60 * 24 * 7 # 7 Days
}
