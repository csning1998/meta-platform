
resource "vault_mount" "kv" {
  provider = vault.downstream

  path = "secret"
  type = "kv-v2"
}

# The SPIRE Parent precedes the Downstream Vault, hence every workstation operator logs in through this mount.
# The JWT-SVIDs of the SPIRE Parent carry the issuer which the server configuration of the SPIRE Parent sets.
resource "vault_jwt_auth_backend" "spire_parent" {
  provider = vault.downstream

  description = "JWT-SVID federation via the OIDC Discovery Provider of the SPIRE Parent"
  path        = local.state.platform_spire_parent.spire_oidc_auth_backend_path
  type        = "jwt"

  oidc_discovery_url    = local.state.platform_spire_parent.spire_oidc_discovery_url
  oidc_discovery_ca_pem = local.state.platform_spire_parent.spire_oidc_discovery_ca_pem
  bound_issuer          = local.state.platform_spire_parent.spire_oidc_discovery_url

  tune {
    listing_visibility = "unauth"
    default_lease_ttl  = "15m"
    max_lease_ttl      = "1h"
  }
}

# Tenant ACL policy definitions map least-privilege KV and PKI paths keyed by tenant identifier.
locals {
  tenant_policy_paths = {
    for name, t in var.tenants : name => merge(
      merge([
        for kv_path in t.kv_paths : {
          "${vault_mount.kv.path}/data/${kv_path}/*" = {
            capabilities = ["create", "read", "update", "delete"]
          }
          "${vault_mount.kv.path}/metadata/${kv_path}/*" = {
            capabilities = ["create", "read", "update", "list", "delete"]
          }
        }
      ]...),
      merge([
        for kv_path in t.kv_read_paths : {
          "${vault_mount.kv.path}/data/${kv_path}"     = { capabilities = ["read"] }
          "${vault_mount.kv.path}/metadata/${kv_path}" = { capabilities = ["read"] }
        }
      ]...),
      merge([
        for pki_role in t.pki_roles : {
          "${local.downstream_vault.pki_mount_path}/issue/${pki_role}" = { capabilities = ["create", "update"] }
        }
      ]...)
    )
  }
}

resource "vault_policy" "tenant" {
  provider = vault.downstream
  for_each = var.tenants

  name   = each.key
  policy = jsonencode({ path = local.tenant_policy_paths[each.key] })
}

# The roles of Child tenants live on the Child mount, which provision-spire-child creates after the SPIRE Child exists.
resource "vault_jwt_auth_backend_role" "tenant" {
  provider = vault.downstream
  for_each = { for name, t in var.tenants : name => t if t.issuer == "parent" }

  backend         = local.jwt_auth.parent.mount_path
  role_name       = each.key
  role_type       = "jwt"
  bound_audiences = [local.jwt_auth.parent.audience]
  bound_subject   = each.value.spiffe_id
  user_claim      = "sub"
  token_policies  = [vault_policy.tenant[each.key].name]
  token_ttl       = 15 * 60
  token_max_ttl   = 60 * 60
}

# The administrator policy grants CRUD on tenant KV, PKI, OIDC, Kubernetes auth mounts, identity, and policies.
resource "vault_policy" "operator" {
  provider = vault.downstream

  name = local.tenant_operator.role_name
  policy = jsonencode({
    path = {
      "${vault_mount.kv.path}/data/${local.project_code}/*" = {
        capabilities = ["create", "read", "update", "delete"]
      }
      "${vault_mount.kv.path}/metadata/${local.project_code}/*" = {
        capabilities = ["create", "read", "update", "list", "delete"]
      }
      "${vault_mount.kv.path}/delete/${local.project_code}/*"  = { capabilities = ["update"] }
      "${vault_mount.kv.path}/destroy/${local.project_code}/*" = { capabilities = ["update"] }

      "sys/mounts/${local.downstream_vault.pki_mount_path}" = { capabilities = ["create", "read", "update", "delete"] }
      "${local.downstream_vault.pki_mount_path}/*"          = { capabilities = ["create", "read", "update", "delete", "list"] }

      "sys/auth/oidc*"        = { capabilities = ["create", "read", "update", "delete", "sudo"] }
      "sys/mounts/auth/oidc*" = { capabilities = ["create", "read", "update", "delete", "sudo"] }
      "auth/oidc/*"           = { capabilities = ["create", "read", "update", "delete", "list"] }

      # Kubernetes auth mounts of the clusters of the tenant. Every mount name starts with the project code.
      "sys/auth"                                = { capabilities = ["read"] }
      "sys/auth/${local.project_code}-*"        = { capabilities = ["create", "read", "update", "delete", "sudo"] }
      "sys/mounts/auth/${local.project_code}-*" = { capabilities = ["create", "read", "update"] }
      "auth/${local.project_code}-*"            = { capabilities = ["create", "read", "update", "delete", "list"] }

      "identity/group"            = { capabilities = ["create", "update"] }
      "identity/group/id/*"       = { capabilities = ["create", "read", "update", "delete"] }
      "identity/group-alias"      = { capabilities = ["create", "update"] }
      "identity/group-alias/id/*" = { capabilities = ["create", "read", "update", "delete"] }
      "sys/policies/acl/*"        = { capabilities = ["create", "read", "update", "delete"] }
    }
  })
}

resource "vault_jwt_auth_backend_role" "operator" {
  provider = vault.downstream

  backend         = local.jwt_auth.parent.mount_path
  role_name       = local.tenant_operator.role_name
  role_type       = "jwt"
  bound_audiences = [local.jwt_auth.parent.audience]
  bound_subject   = "spiffe://${local.trust_domain}${local.tenant_operator.spiffe_path}"
  user_claim      = "sub"

  token_policies = [vault_policy.operator.name]
  token_ttl      = 15 * 60
  token_max_ttl  = 60 * 60
}

