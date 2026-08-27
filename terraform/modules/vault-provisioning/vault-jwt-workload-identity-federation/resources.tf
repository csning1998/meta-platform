
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
  }
}

resource "vault_policy" "this" {
  name = "jwt-policy-${var.role_name}"
  policy = jsonencode({
    path = merge(
      {
        for p in var.kv_read_paths :
        "${var.kv_mount_path}/data/${p}" => { capabilities = ["read"] }
      },
      {
        for p in var.kv_read_paths :
        "${var.kv_mount_path}/metadata/${p}" => { capabilities = ["read", "list"] }
      }
    )
  })
}

resource "vault_jwt_auth_backend_role" "this" {
  backend    = var.auth_backend_path
  role_name  = var.role_name
  role_type  = "jwt"
  user_claim = "project_path"
  bound_claims = {
    project_path  = var.project_path
    ref_protected = var.ref_protected ? "true" : "false"
    ref_type      = var.ref_type
  }
  token_policies = [vault_policy.this.name]
  token_ttl      = var.token_ttl
  token_max_ttl  = var.token_max_ttl
}
