
# Kubernetes auth mount, roles, and policies by which the in-cluster cert-manager and External Secrets Operator log in to Vault. The caller selects the Vault through the providers map.
locals {
  identity = var.kubernetes_identity_config

  auth_path            = "${var.cluster_name}-service-account-token-provider"
  issuer_role_name     = var.cluster_name
  issue_path           = "sign"
  external_secret_role = "${var.cluster_name}-external-secrets"

  pki_role_name      = coalesce(var.pki_config.role_name, one(vault_pki_secret_backend_role.cluster_issuer[*].name))
  issuer_policy_name = coalesce(var.pki_config.issuer_policy_name, one(vault_policy.cluster_issuer[*].name))

  external_secrets_policy_name = var.external_secrets_config == null ? null : coalesce(var.external_secrets_config.policy_name, one(vault_policy.external_secrets[*].name))
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = local.auth_path
}

resource "vault_pki_secret_backend_role" "cluster_issuer" {
  count = var.pki_config.role_name == null ? 1 : 0

  backend = var.pki_config.mount_path
  name    = local.issuer_role_name

  allowed_domains    = var.pki_config.role_allowed_domains
  allow_subdomains   = true
  allow_glob_domains = false
  allow_bare_domains = true
  allow_ip_sans      = var.pki_config.role_allow_ip_sans
  require_cn         = false
  enforce_hostnames  = true
  allow_any_name     = false

  key_type    = "ec"
  key_bits    = 256
  key_usage   = ["DigitalSignature"]
  server_flag = true
  client_flag = true

  max_ttl = 60 * 60 * 24 * 90 # 90 Days
  ttl     = 60 * 60 * 24 * 30 # 30 Days

  ou = var.pki_config.role_ou
}

# The suffix keeps the policy name apart from tenant policies which carry the plain cluster name.
resource "vault_policy" "cluster_issuer" {
  count = var.pki_config.issuer_policy_name == null ? 1 : 0

  name = "${local.issuer_role_name}-cluster-issuer"
  policy = jsonencode({
    path = {
      "${var.pki_config.mount_path}/${local.issue_path}/${local.pki_role_name}" = {
        capabilities = ["create", "update"]
      }
    }
  })
}

resource "vault_kubernetes_auth_backend_role" "cluster_issuer" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = local.issuer_role_name
  bound_service_account_names      = [local.identity.cluster_issuer_service_account]
  bound_service_account_namespaces = [local.identity.cert_manager_namespace]
  token_policies                   = [local.issuer_policy_name]
  token_ttl                        = 60 * 15
  token_max_ttl                    = 60 * 60
}

# External Secrets Operator reads the listed KV paths and nothing else.
resource "vault_policy" "external_secrets" {
  count = var.external_secrets_config == null ? 0 : (var.external_secrets_config.policy_name == null ? 1 : 0)

  name = local.external_secret_role
  policy = jsonencode({
    path = merge([
      for kv_path in var.external_secrets_config.kv_paths : {
        "${var.external_secrets_config.kv_mount_path}/data/${kv_path}"     = { capabilities = ["read"] }
        "${var.external_secrets_config.kv_mount_path}/metadata/${kv_path}" = { capabilities = ["read"] }
      }
    ]...)
  })
}

resource "vault_kubernetes_auth_backend_role" "external_secrets" {
  count = var.external_secrets_config == null ? 0 : 1

  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = local.external_secret_role
  bound_service_account_names      = [local.identity.external_secrets_service_account]
  bound_service_account_namespaces = [local.identity.external_secrets_namespace]
  token_policies                   = [local.external_secrets_policy_name]
  token_ttl                        = 60 * 15
  token_max_ttl                    = 60 * 60
}

# The issuer signs at <mount>/<issue path>/<role>, and the role of the Kubernetes auth mount carries the same name as the PKI role.
check "issuer_role_matches_pki_role" {
  assert {
    condition     = local.pki_role_name == local.issuer_role_name
    error_message = "The PKI role MUST carry the name of the cluster, which is the role name of the ClusterIssuer."
  }
}
