
# Define Terraform Administrative Policy
resource "vault_policy" "terraform_admin" {
  provider = vault.bastion
  name     = "terraform-admin-policy"
  policy   = <<EOT
# [1] Data Operations: Includes read, create, update, and soft delete of the latest version
path "secret/data/meta-platform/*" {
  capabilities = ["read", "create", "update", "delete"]
}

# [2] Metadata Operations: Required for Terraform to read and purge metadata during plan and destroy
path "secret/metadata/meta-platform/*" {
  capabilities = ["read", "list", "delete"]
}

# [3] Version Deletion: Allows Terraform to mark specific old versions as deleted
path "secret/delete/meta-platform/*" {
  capabilities = ["update"]
}

# [4] Permanent Destruction: Allows Terraform to perform forced physical removal (Destroy)
path "secret/destroy/meta-platform/*" {
  capabilities = ["update"]
}

# [5] Bootstrap Leaf Issuance: Required by downstream layers requesting certificates
# from the Bootstrap Issuing Intermediate before the Production Vault is reachable
path "${local.bastion_pki_inter_mount_path}/issue/*" {
  capabilities = ["create", "update"]
}

# [6] Mount Metadata Read: vault_pki_secret_backend_cert reads mount config on refresh
path "sys/mounts/${local.bastion_pki_inter_mount_path}" {
  capabilities = ["read"]
}

# [7] Intermediate Signing: allows the Production Vault's intermediate CSR to be signed
# by the Bootstrap Issuing Intermediate
path "${local.bastion_pki_inter_mount_path}/root/sign-intermediate" {
  capabilities = ["create", "update"]
}

# [8] JWT Auth Backend Management: mount/unmount the gitlab-saas-jwt backend
# only. Scoped to the exact name so this role cannot delete a future
# gitlab-instance-jwt backend it does not own.
path "sys/auth/gitlab-saas-jwt" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# [8a] Auth Mount Table Read: the provider reads the full mount table to look
# up a single backend by path. Read-only, lists paths/types/accessors only.
path "sys/auth" {
  capabilities = ["read"]
}

# [8b] JWT Auth Backend Read/Tune: the provider reads and tunes mount config
# via sys/mounts/auth/*, a separate endpoint from sys/auth/*. The trailing
# glob is scoped safely here because "gitlab-saas-jwt" is already the full,
# unique backend name, unlike the earlier "gitlab*" prefix.
path "sys/mounts/auth/gitlab-saas-jwt*" {
  capabilities = ["read", "create", "update"]
}

# [8c] Exact-Path Scoping: Vault ACL `*` only globs as the final path
# character, so the paths below name the backend exactly instead of "gitlab*"
path "sys/auth/gitlab-saas-jwt/tune" {
  capabilities = ["create", "read", "update"]
}

# [9] JWT Backend Config: writes oidc_discovery_url and related backend settings
path "auth/gitlab-saas-jwt/config" {
  capabilities = ["create", "read", "update"]
}

# [10] JWT Role Management: per-consumer roles under a GitLab JWT auth backend
path "auth/gitlab-saas-jwt/role/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# [11] JWT Policy Management: scoped to the federation module's naming convention
path "sys/policies/acl/jwt-policy-*" {
  capabilities = ["create", "read", "update", "delete"]
}
EOT
}

# Enable AppRole auth backend
resource "vault_auth_backend" "approle" {
  provider = vault.bastion
  type     = "approle"
}

# Enable kv-v2 engine
resource "vault_mount" "kv" {
  provider = vault.bastion
  path     = "secret"
  type     = "kv-v2"
}

# Create the Terraform AppRole
resource "vault_approle_auth_backend_role" "terraform_admin" {
  provider       = vault.bastion
  backend        = vault_auth_backend.approle.path
  role_name      = "terraform-admin-role"
  token_policies = [vault_policy.terraform_admin.name]
  token_ttl      = 3600
  token_max_ttl  = 14400
}

resource "vault_approle_auth_backend_role_secret_id" "terraform_admin" {
  provider  = vault.bastion
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.terraform_admin.role_name
}

resource "vault_kv_secret_v2" "terraform_admin_auth" {
  provider = vault.bastion
  mount    = vault_mount.kv.path
  name     = "meta-platform/credentials"
  data_json = jsonencode({
    role_id   = vault_approle_auth_backend_role.terraform_admin.role_id
    secret_id = vault_approle_auth_backend_role_secret_id.terraform_admin.secret_id
  })
}
