
resource "vault_pki_secret_backend_cert" "stats" {
  backend     = local.state.vault_bastion.bastion_pki_inter_mount_path
  name        = local.haproxy_pki_role_name
  common_name = local.state.network.global_pki_map[local.haproxy_pki_role_name].dns_san[0]
  alt_names   = local.state.network.global_pki_map[local.haproxy_pki_role_name].dns_san
  ip_sans     = module.context.svc_network.node_ips

  auto_renew            = true
  min_seconds_remaining = 60 * 60 * 24 * 7 # 7 Days
}
