
# Configures Bastion Vault authentication and PKI roles for the in-cluster cert-manager trust chain.

locals {
  # Grants issuance domains required by Cilium Hubble server and relay gRPC mTLS endpoints.
  hubble_tls_domains = ["hubble-grpc.cilium.io", "hubble-relay.cilium.io"]
  kv_hubble_ui_path  = "${local.kv_paths.addon}-hubble-ui"
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = local.cluster_issuer.auth_path
}

# Provisions the Bastion PKI role authorizing cluster leaf certificate issuance for catalog ingress and Hubble endpoints.
resource "vault_pki_secret_backend_role" "cluster_issuer" {
  backend = local.cluster_issuer.pki_mount_path
  name    = local.cluster_issuer.role_name

  allowed_domains = concat(
    local.state.foundation_libvirt_resources.foundation_pki.map["${local.svc_context.s_name}-${local.svc_context.c_name}"].dns_san,
    local.hubble_tls_domains
  )
  allow_subdomains   = true
  allow_glob_domains = false
  allow_bare_domains = true
  allow_ip_sans      = false
  require_cn         = false
  enforce_hostnames  = true
  allow_any_name     = false

  key_type    = "any"
  key_usage   = ["DigitalSignature", "KeyEncipherment"]
  server_flag = true
  client_flag = true

  max_ttl = 60 * 60 * 24 * 90 # 90 Days
  ttl     = 60 * 60 * 24 * 30 # 30 Days

  ou = local.state.foundation_libvirt_resources.foundation_pki.map["${local.svc_context.s_name}-${local.svc_context.c_name}"].ou
}

resource "vault_policy" "cluster_issuer" {
  name = local.cluster_issuer.role_name
  policy = jsonencode({
    path = {
      "${local.cluster_issuer.pki_mount_path}/sign/${vault_pki_secret_backend_role.cluster_issuer.name}" = {
        capabilities = ["create", "update"]
      }
    }
  })
}

resource "vault_kubernetes_auth_backend_role" "cluster_issuer" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = local.cluster_issuer.role_name
  bound_service_account_names      = [local.cluster_issuer.service_account]
  bound_service_account_namespaces = [local.cluster_issuer.namespace]
  token_policies                   = [vault_policy.cluster_issuer.name]
  token_ttl                        = 60 * 15
  token_max_ttl                    = 60 * 60
}

# Grants External Secrets Operator read access to minted Hubble UI ingress authentication secrets.
resource "vault_policy" "external_secrets" {
  name = local.external_secrets.role_name
  policy = jsonencode({
    path = {
      "secret/data/${local.kv_hubble_ui_path}" = {
        capabilities = ["read"]
      }
      "secret/metadata/${local.kv_hubble_ui_path}" = {
        capabilities = ["read"]
      }
    }
  })
}

resource "vault_kubernetes_auth_backend_role" "external_secrets" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = local.external_secrets.role_name
  bound_service_account_names      = [local.external_secrets.service_account]
  bound_service_account_namespaces = [local.external_secrets.namespace]
  token_policies                   = [vault_policy.external_secrets.name]
  token_ttl                        = 60 * 15
  token_max_ttl                    = 60 * 60
}
