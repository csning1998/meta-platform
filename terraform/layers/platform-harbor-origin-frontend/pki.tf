
# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item D.
# The role name equals the identity string of the service, which the tenant ACL scopes by the owner code prefix.
resource "vault_pki_secret_backend_role" "listener" {
  backend = local.state.vault_bastion.bastion_vault_pki.intermediate_mount_path
  name    = local.harbor_pki_role_name

  allowed_domains    = local.state.network.foundation_pki.map[module.context.primary_context.pki_key].dns_san
  allow_subdomains   = false
  allow_glob_domains = false
  allow_bare_domains = true
  allow_ip_sans      = true
  require_cn         = true
  enforce_hostnames  = true
  allow_any_name     = false

  key_usage   = ["DigitalSignature", "KeyEncipherment"]
  server_flag = true
  client_flag = true

  max_ttl = 60 * 60 * 24 * 90 # 90 Days
  ttl     = 60 * 60 * 24 * 30 # 30 Days

  ou = local.state.network.foundation_pki.map[module.context.primary_context.pki_key].ou
}

resource "vault_pki_secret_backend_cert" "listener" {
  backend     = vault_pki_secret_backend_role.listener.backend
  name        = vault_pki_secret_backend_role.listener.name
  common_name = local.state.network.foundation_pki.map[module.context.primary_context.pki_key].dns_san[0]
  alt_names   = local.state.network.foundation_pki.map[module.context.primary_context.pki_key].dns_san
  ip_sans     = concat(local.harbor_node_ips, [module.context.primary_net_config.lb_config.vip])

  # Rotate the bootstrap leaf before expiry while Vault Agent is inactive in the bootstrapping stage.
  auto_renew            = true
  min_seconds_remaining = 60 * 60 * 24 * 7 # 7 Days
}
