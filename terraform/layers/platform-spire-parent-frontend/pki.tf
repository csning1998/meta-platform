
# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item D.
resource "vault_pki_secret_backend_cert" "oidc_discovery" {
  backend     = data.terraform_remote_state.vault_bastion.outputs.bastion_pki_inter_mount_path
  name        = "spire-parent-frontend"
  common_name = module.context.svc_fqdn
  alt_names   = [module.context.svc_fqdn]
  ip_sans     = module.context.svc_network.node_ips

  # Rotate the bootstrap leaf before expiry while Vault Agent is inactive in the bootstrapping stage.
  auto_renew            = true
  min_seconds_remaining = 60 * 60 * 24 * 7 # 7 Days
}
