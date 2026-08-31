
# Defines administrative ACL policy capabilities for Bastion Vault infrastructure management.
resource "vault_policy" "terraform_admin" {
  provider = vault.bastion
  name     = "terraform-admin-policy"
  policy   = <<EOT
# [1] KV v2 Data Operations: Authorizes read, create, update, and soft-delete capabilities for secret payloads.
path "secret/data/meta-platform/*" {
  capabilities = ["read", "create", "update", "delete"]
}

# [2] KV v2 Metadata Operations: Authorizes read, list, and delete capabilities for secret metadata required during plan execution and resource destruction.
path "secret/metadata/meta-platform/*" {
  capabilities = ["read", "list", "delete"]
}

# [3] KV v2 Version Deletion: Authorizes update capabilities on secret version deletion endpoints.
path "secret/delete/meta-platform/*" {
  capabilities = ["update"]
}

# [4] KV v2 Version Destruction: Authorizes update capabilities on permanent secret destruction endpoints.
path "secret/destroy/meta-platform/*" {
  capabilities = ["update"]
}

# [4a] KV v2 Preflight Mount Lookup: Authorizes the Vault CLI's KV v1/v2 mount-type detection request issued before every kv read or write against the secret/ mount.
path "sys/internal/ui/mounts/secret/*" {
  capabilities = ["read"]
}

# [4b] Credential Bootstrap Data Operations: Authorizes read, create, update, and soft-delete capabilities for bootstrap credential payloads.
path "secret/data/meta-platform-credentials/*" {
  capabilities = ["read", "create", "update", "delete"]
}

# [4c] Credential Bootstrap Metadata Operations: Authorizes read, list, and delete capabilities for bootstrap credential metadata.
path "secret/metadata/meta-platform-credentials/*" {
  capabilities = ["read", "list", "delete"]
}

# [4d] Credential Bootstrap Version Deletion: Authorizes update capabilities on bootstrap credential version deletion endpoints.
path "secret/delete/meta-platform-credentials/*" {
  capabilities = ["update"]
}

# [4e] Credential Bootstrap Version Destruction: Authorizes update capabilities on permanent bootstrap credential destruction endpoints.
path "secret/destroy/meta-platform-credentials/*" {
  capabilities = ["update"]
}

# [5] Bootstrap Certificate Issuance: Authorizes leaf certificate issuance against the bootstrap issuing intermediate authority prior to production Vault availability.
path "${local.bastion_pki_inter_mount_path}/issue/*" {
  capabilities = ["create", "update"]
}

# [6] PKI Mount Configuration Read: Authorizes read access to intermediate PKI mount configurations required for provider state refresh.
path "sys/mounts/${local.bastion_pki_inter_mount_path}" {
  capabilities = ["read"]
}

# [7] Intermediate CA Signing: Authorizes intermediate certificate signing requests submitted to the bootstrap issuing intermediate.
path "${local.bastion_pki_inter_mount_path}/root/sign-intermediate" {
  capabilities = ["create", "update"]
}

# [8] SaaS GitLab JWT Auth Backend Management: Authorizes lifecycle management scoped exclusively to sys/auth/gitlab-saas-jwt.
path "sys/auth/gitlab-saas-jwt" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# [8a] Auth Mount Table Inspection: Authorizes read-only access to sys/auth for auth backend path resolution.
path "sys/auth" {
  capabilities = ["read"]
}

# [8b] SaaS GitLab JWT Auth Mount Configuration: Authorizes configuration read and tuning operations under sys/mounts/auth/gitlab-saas-jwt*.
path "sys/mounts/auth/gitlab-saas-jwt*" {
  capabilities = ["read", "create", "update"]
}

# [8c] SaaS GitLab JWT Auth Mount Tuning: Authorizes explicit tuning capabilities for sys/auth/gitlab-saas-jwt/tune.
path "sys/auth/gitlab-saas-jwt/tune" {
  capabilities = ["create", "read", "update"]
}

# [9] SaaS GitLab OIDC Configuration: Authorizes writing OIDC discovery URL and backend parameter settings under auth/gitlab-saas-jwt/config.
path "auth/gitlab-saas-jwt/config" {
  capabilities = ["create", "read", "update"]
}

# [10] SaaS GitLab JWT Role Provisioning: Authorizes creation, reading, updating, and deletion of roles under auth/gitlab-saas-jwt/role/*.
path "auth/gitlab-saas-jwt/role/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# [11] Federation Policy Management: Authorizes ACL policy CRUD operations scoped to jwt-policy-* naming conventions.
path "sys/policies/acl/jwt-policy-*" {
  capabilities = ["create", "read", "update", "delete"]
}

# [12] SPIRE OIDC JWT Auth Backend Management: Authorizes lifecycle management scoped exclusively to sys/auth/spire-oidc-jwt.
path "sys/auth/spire-oidc-jwt" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# [12a] SPIRE OIDC JWT Auth Mount Configuration: Authorizes configuration read and tuning operations under sys/mounts/auth/spire-oidc-jwt.
path "sys/mounts/auth/spire-oidc-jwt" {
  capabilities = ["read", "create", "update"]
}

# [13] SPIRE OIDC Discovery Configuration: Authorizes writing OIDC discovery URL parameters under auth/spire-oidc-jwt/config.
path "auth/spire-oidc-jwt/config" {
  capabilities = ["create", "read", "update"]
}

# [14] SPIRE Workload Identity Role Provisioning: Authorizes creation, reading, updating, and deletion of SPIFFE-bound roles under auth/spire-oidc-jwt/role/*.
path "auth/spire-oidc-jwt/role/*" {
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
