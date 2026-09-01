
# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 4 Item D, Item E.
# JWT-backed auth mounts share an identical five-grant ACL template.
locals {
  jwt_auth_backends = [
    { path_key = "gitlab-saas-jwt", label = "SaaS GitLab" },
    { path_key = "spire-oidc-jwt", label = "SPIRE OIDC" },
  ]

  jwt_auth_backend_policy = join("\n\n", [
    for backend in local.jwt_auth_backends : trimspace(<<-EOT
      # ${backend.label} JWT Auth Backend Management.
      path "sys/auth/${backend.path_key}" {
        capabilities = ["create", "read", "update", "delete", "sudo"]
      }

      # ${backend.label} JWT Auth Mount Configuration.
      path "sys/mounts/auth/${backend.path_key}*" {
        capabilities = ["read", "create", "update"]
      }

      # ${backend.label} JWT Auth Mount Tuning.
      path "sys/auth/${backend.path_key}/tune" {
        capabilities = ["create", "read", "update"]
      }

      # ${backend.label} OIDC Configuration.
      path "auth/${backend.path_key}/config" {
        capabilities = ["create", "read", "update"]
      }

      # ${backend.label} Role Provisioning.
      path "auth/${backend.path_key}/role/*" {
        capabilities = ["create", "read", "update", "delete"]
      }
      EOT
    )
  ])
}

# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 4 Item E.
resource "vault_policy" "terraform_admin" {
  provider = vault.bastion
  name     = "terraform-admin-policy"
  policy   = <<EOT
# [1] KV v2 Data Operations.
path "secret/data/meta-platform/*" {
  capabilities = ["read", "create", "update", "delete"]
}

# [2] KV v2 Metadata Operations.
path "secret/metadata/meta-platform/*" {
  capabilities = ["read", "list", "delete"]
}

# [3] KV v2 Version Deletion.
path "secret/delete/meta-platform/*" {
  capabilities = ["update"]
}

# [4] KV v2 Version Destruction.
path "secret/destroy/meta-platform/*" {
  capabilities = ["update"]
}

# [4a] KV v2 Preflight Mount Lookup.
path "sys/internal/ui/mounts/secret/*" {
  capabilities = ["read"]
}

# [4b] Credential Bootstrap Data Operations.
path "secret/data/meta-platform-credentials/*" {
  capabilities = ["read", "create", "update", "delete"]
}

# [4c] Credential Bootstrap Metadata Operations.
path "secret/metadata/meta-platform-credentials/*" {
  capabilities = ["read", "list", "delete"]
}

# [4d] Credential Bootstrap Version Deletion.
path "secret/delete/meta-platform-credentials/*" {
  capabilities = ["update"]
}

# [4e] Credential Bootstrap Version Destruction.
path "secret/destroy/meta-platform-credentials/*" {
  capabilities = ["update"]
}

# [5] Bootstrap Certificate Issuance.
path "${local.bastion_pki_inter_mount_path}/issue/*" {
  capabilities = ["create", "update"]
}

# [6] PKI Mount Configuration Read.
path "sys/mounts/${local.bastion_pki_inter_mount_path}" {
  capabilities = ["read"]
}

# [7] Intermediate CA Signing.
path "${local.bastion_pki_inter_mount_path}/root/sign-intermediate" {
  capabilities = ["create", "update"]
}

# [8] Auth Mount Table Inspection.
path "sys/auth" {
  capabilities = ["read"]
}

${local.jwt_auth_backend_policy}

# [9] Federation Policy Management.
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
  token_ttl      = 60 * 60     # 1 Hour
  token_max_ttl  = 60 * 60 * 4 # 4 Hours
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
