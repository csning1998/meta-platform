
locals {
  vault_listener_dns_names = concat(
    data.terraform_remote_state.metadata.outputs.foundation_pki.map[module.context.primary_context.pki_key].dns_san,
    ["vault", "localhost"]
  )
}

# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item D.
# The role name equals the identity string of the service, which the tenant ACL scopes by the owner code prefix.
resource "vault_pki_secret_backend_role" "vault_listener" {
  provider = vault.bastion
  backend  = data.terraform_remote_state.vault_bastion.outputs.bastion_vault_pki.intermediate_mount_path
  name     = module.context.svc_identity.cluster_name

  allowed_domains    = local.vault_listener_dns_names
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

  ou = data.terraform_remote_state.metadata.outputs.foundation_pki.map[module.context.primary_context.pki_key].ou
}

resource "vault_pki_secret_backend_cert" "vault_listener" {
  provider    = vault.bastion
  backend     = vault_pki_secret_backend_role.vault_listener.backend
  name        = vault_pki_secret_backend_role.vault_listener.name
  common_name = module.context.svc_fqdn

  alt_names = local.vault_listener_dns_names
  ip_sans = concat(
    ["127.0.0.1", module.context.primary_net_config.lb_config.vip],
    module.context.svc_network.node_ips
  )
}
