
# The SPIRE Server signs its own intermediate CA against the Bastion PKI intermediate.
# The AppRole below is the only identity which may call sign-intermediate.
resource "vault_policy" "spire_upstream_authority" {
  name   = "${module.context.svc_identity.cluster_name}-upstream-authority"
  policy = <<EOT
path "${local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_mount_path}/root/sign-intermediate" {
  capabilities = ["create", "update"]
}
EOT
}

resource "vault_approle_auth_backend_role" "spire_upstream_authority" {
  backend        = local.state.foundation_vault_bastion.bastion_vault_auth.approle_mount_path
  role_name      = vault_policy.spire_upstream_authority.name
  token_policies = [vault_policy.spire_upstream_authority.name]
  token_ttl      = 60 * 60     # 1 Hour
  token_max_ttl  = 60 * 60 * 4 # 4 Hours
}

resource "vault_approle_auth_backend_role_secret_id" "spire_upstream_authority" {
  backend   = vault_approle_auth_backend_role.spire_upstream_authority.backend
  role_name = vault_approle_auth_backend_role.spire_upstream_authority.role_name
}

# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item D.
# The role name equals the identity string of the service, which the tenant ACL scopes by the owner code prefix.
resource "vault_pki_secret_backend_role" "leaf" {
  backend = local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_mount_path
  name    = module.context.svc_identity.cluster_name

  allowed_domains    = local.state.foundation_libvirt_resources.foundation_pki.map[module.context.primary_context.pki_key].dns_san
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

  ou = local.state.foundation_libvirt_resources.foundation_pki.map[module.context.primary_context.pki_key].ou
}

resource "vault_pki_secret_backend_cert" "oidc_discovery" {
  backend     = vault_pki_secret_backend_role.leaf.backend
  name        = vault_pki_secret_backend_role.leaf.name
  common_name = module.context.svc_fqdn
  alt_names   = [module.context.svc_fqdn]
  ip_sans     = module.context.svc_network.node_ips

  # Rotate the bootstrap leaf before expiry while Vault Agent is inactive in the bootstrapping stage.
  auto_renew            = true
  min_seconds_remaining = 60 * 60 * 24 * 7 # 7 Days
}

# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item E, Section 4.
# Per-consumer role bindings SHALL be provisioned independently via vault-spiffe-workload-identity-federation.
resource "vault_jwt_auth_backend" "spire_oidc" {
  depends_on  = [module.platform_spire_parent]
  description = "SPIRE Parent workload JWT-SVID federation via the OIDC Discovery Provider"
  path        = "${module.context.svc_identity.cluster_name}-jwt-svid-provider"
  type        = "jwt"

  oidc_discovery_url    = "https://${local.spire_parent_node_ip}:${local.spire_oidc_port}"
  oidc_discovery_ca_pem = local.bastion_pki_chain_pem

  tune {
    listing_visibility = "unauth"
    default_lease_ttl  = "5m"
    max_lease_ttl      = "1h"
  }
}
