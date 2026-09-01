
# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item E, Section 4.
# Per-consumer role bindings SHALL be provisioned independently via vault-spiffe-workload-identity-federation.
resource "vault_jwt_auth_backend" "spire_oidc" {
  depends_on  = [module.platform_spire_parent]
  description = "SPIRE Parent workload JWT-SVID federation via the OIDC Discovery Provider"
  path        = "spire-oidc-jwt"
  type        = "jwt"

  oidc_discovery_url    = "https://${local.spire_parent_node_ip}:${local.spire_oidc_port}"
  oidc_discovery_ca_pem = local.bastion_pki_chain_pem

  tune {
    listing_visibility = "unauth"
    default_lease_ttl  = "5m"
    max_lease_ttl      = "1h"
  }

}
