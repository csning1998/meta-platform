
# SPIRE Server upstream authority: authorizes signing SPIRE's own intermediate CA against the Bootstrap Issuing Intermediate.
resource "vault_policy" "spire_upstream_authority" {
  provider = vault.bastion
  name     = "spire-upstream-authority-policy"
  policy   = <<EOT
# [1] Intermediate CA Signing: Authorizes the SPIRE Server upstream authority plugin to submit its own intermediate CSR for signing.
path "${local.bastion_pki_inter_mount_path}/root/sign-intermediate" {
  capabilities = ["create", "update"]
}
EOT
}

resource "vault_approle_auth_backend_role" "spire_upstream_authority" {
  provider       = vault.bastion
  backend        = vault_auth_backend.approle.path
  role_name      = "spire-upstream-authority-role"
  token_policies = [vault_policy.spire_upstream_authority.name]
  token_ttl      = 3600
  token_max_ttl  = 14400
}

resource "vault_approle_auth_backend_role_secret_id" "spire_upstream_authority" {
  provider  = vault.bastion
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.spire_upstream_authority.role_name
}
