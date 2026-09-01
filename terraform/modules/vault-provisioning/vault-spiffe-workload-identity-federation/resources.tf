
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
  }
}

resource "vault_policy" "this" {
  # Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 5 Item B.
  name = "jwt-policy-${var.name}"
  policy = jsonencode({
    path = merge(
      {
        "${var.pki_mount_path}/issue/${var.vault_role_name}" = { capabilities = ["create", "update"] }
      },
      var.extra_policy_paths
    )
  })
}

resource "vault_jwt_auth_backend_role" "this" {
  backend         = var.auth_backend_path
  role_name       = var.name
  role_type       = "jwt"
  bound_audiences = [var.audience]
  bound_subject   = var.spiffe_id
  user_claim      = "sub"
  token_policies  = ["default", vault_policy.this.name]
  token_ttl       = var.token_ttl
  token_max_ttl   = var.token_max_ttl
}
