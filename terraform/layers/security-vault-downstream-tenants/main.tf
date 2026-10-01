
resource "vault_mount" "kv" {
  provider = vault.downstream

  path = "secret"
  type = "kv-v2"
}

# JWT auth backend establishes downstream tenant federation via SPIRE child OIDC discovery endpoint.
resource "vault_jwt_auth_backend" "spire_child" {
  provider = vault.downstream

  description = "Tenant workload JWT-SVID federation via the OIDC Discovery Provider of the SPIRE Child"
  path        = local.state.provision_spire_child.spire_child.jwt_svid_auth_mount_path
  type        = "jwt"

  oidc_discovery_url    = local.state.provision_spire_child.spire_child.jwt_issuer
  oidc_discovery_ca_pem = local.bastion_pki_chain_pem
  bound_issuer          = local.state.provision_spire_child.spire_child.jwt_issuer

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

resource "vault_jwt_auth_backend_role" "tenant" {
  provider = vault.downstream
  for_each = var.tenants

  backend         = local.jwt_auth[each.value.issuer].mount_path
  role_name       = each.key
  role_type       = "jwt"
  bound_audiences = [local.jwt_auth[each.value.issuer].audience]
  bound_subject   = each.value.spiffe_id
  user_claim      = "sub"
  token_policies  = [vault_policy.tenant[each.key].name]
  token_ttl       = 15 * 60
  token_max_ttl   = 60 * 60
}

# The Parent mount stays until every downstream consumer logs in through the SPIRE Child, and then this mount and its role MUST be removed.
resource "vault_jwt_auth_backend" "spire_parent" {
  provider = vault.downstream

  description = "Local Terraform operator JWT-SVID federation via the OIDC Discovery Provider of the SPIRE Parent"
  path        = local.state.platform_spire_parent.spire_oidc_auth_backend_path
  type        = "jwt"

  oidc_discovery_url    = local.state.platform_spire_parent.spire_oidc_discovery_url
  oidc_discovery_ca_pem = local.bastion_pki_chain_pem

  tune {
    listing_visibility = "unauth"
    default_lease_ttl  = "15m"
    max_lease_ttl      = "1h"
  }
}

# Operator policy grants administrative CRUD permissions on tenant KV, PKI, OIDC, and identity endpoints.
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

      "identity/group"            = { capabilities = ["create", "update"] }
      "identity/group/id/*"       = { capabilities = ["create", "read", "update", "delete"] }
      "identity/group-alias"      = { capabilities = ["create", "update"] }
      "identity/group-alias/id/*" = { capabilities = ["create", "read", "update", "delete"] }
      "sys/policies/acl/*"        = { capabilities = ["create", "read", "update", "delete"] }
    }
  })
}

# Workstation Terraform operators authenticate against downstream Vault using SPIRE Child JWT-SVIDs.
resource "vault_jwt_auth_backend_role" "operator" {
  provider = vault.downstream

  backend         = vault_jwt_auth_backend.spire_child.path
  role_name       = local.tenant_operator.role_name
  role_type       = "jwt"
  bound_audiences = [local.jwt_auth.child.audience]
  user_claim      = "sub"

  bound_claims_type = "glob"
  bound_claims      = { sub = local.tenant_operator.spiffe_ids }

  token_policies = [vault_policy.operator.name]
  token_ttl      = 15 * 60
  token_max_ttl  = 60 * 60
}

# Legacy binding of the SPIRE Parent, retained only until the Parent mount is removed.
resource "vault_jwt_auth_backend_role" "operator_parent" {
  provider = vault.downstream

  backend         = vault_jwt_auth_backend.spire_parent.path
  role_name       = local.tenant_operator.role_name
  role_type       = "jwt"
  bound_audiences = [local.jwt_auth.parent.audience]
  user_claim      = "sub"

  bound_claims_type = "glob"
  bound_claims      = { sub = local.tenant_operator.spiffe_ids }

  token_policies = [vault_policy.operator.name]
  token_ttl      = 15 * 60
  token_max_ttl  = 60 * 60
}
