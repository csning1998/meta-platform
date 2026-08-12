
# Enable KV v2 engine for uninitialized Raft storage backends lacking default mounts.
resource "vault_mount" "kv" {
  provider = vault.production
  path     = "secret"
  type     = "kv-v2"
}

resource "vault_policy" "production_admin" {
  provider = vault.production
  name     = "production-terraform-admin-policy"
  policy   = <<EOT
path "secret/data/meta-platform/*" {
  capabilities = ["read", "create", "update", "delete"]
}

path "secret/metadata/meta-platform/*" {
  capabilities = ["read", "list", "delete"]
}

path "secret/delete/meta-platform/*" {
  capabilities = ["update"]
}

path "secret/destroy/meta-platform/*" {
  capabilities = ["update"]
}

path "sys/mounts/${local.prod_pki_issuer_mount_path}" {
  capabilities = ["create", "read", "update", "delete"]
}

path "${local.prod_pki_issuer_mount_path}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/auth/workload-approle*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "sys/mounts/auth/workload-approle*" {
  capabilities = ["read"]
}

path "sys/auth/oidc*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "sys/mounts/auth/oidc*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "auth/workload-approle/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/oidc/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "identity/group" {
  capabilities = ["create", "update"]
}

path "identity/group/id/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "identity/group-alias" {
  capabilities = ["create", "update"]
}

path "identity/group-alias/id/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete"]
}
EOT
}

resource "vault_auth_backend" "approle" {
  provider = vault.production
  type     = "approle"
}

resource "vault_approle_auth_backend_role" "production_admin" {
  provider       = vault.production
  backend        = vault_auth_backend.approle.path
  role_name      = "production-terraform-admin-role"
  token_policies = [vault_policy.production_admin.name]
  token_ttl      = 3600
  token_max_ttl  = 14400
}

resource "vault_approle_auth_backend_role_secret_id" "production_admin" {
  provider  = vault.production
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.production_admin.role_name
}
