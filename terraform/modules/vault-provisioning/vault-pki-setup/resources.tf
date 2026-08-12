
locals {
  pki_api_base_url = "${var.prod_vault_endpoint}/v1/${vault_mount.pki_issuer.path}"
}

# 1. PKI Secrets Engine
resource "vault_mount" "pki_issuer" {
  provider    = vault.production
  path        = var.pki_engine_config.path
  type        = "pki"
  description = "Production PKI Engine for internal services"

  default_lease_ttl_seconds = var.pki_engine_config.default_lease_ttl_seconds
  max_lease_ttl_seconds     = var.pki_engine_config.max_lease_ttl_seconds
}

# Hierarchical PKI configuration. Root CA resides in Bootstrap Vault; this engine retains only the signed Issuer CA.

# 2a. Generate Issuer CA CSR in Production PKI engine.
resource "vault_pki_secret_backend_intermediate_cert_request" "pki_issuer_csr" {
  provider = vault.production
  backend  = vault_mount.pki_issuer.path

  type        = "internal"
  common_name = var.pki_settings.intermediate_ca_common_name
  key_type    = "rsa"
  key_bits    = 4096

  # Force key regeneration on mount recreation because provider state lacks a Read implementation for this resource.
  key_name = "issuer-${vault_mount.pki_issuer.accessor}"
}

# 2b. Sign Issuer CA CSR using Bootstrap Vault Intermediate CA.
resource "vault_pki_secret_backend_root_sign_intermediate" "pki_issuer_signed" {
  provider = vault.bootstrap
  backend  = var.bastion_pki_inter_mount_path

  csr                  = vault_pki_secret_backend_intermediate_cert_request.pki_issuer_csr.csr
  common_name          = var.pki_settings.intermediate_ca_common_name
  format               = "pem"
  ttl                  = 60 * 60 * 24 * 365 # 1 Year
  exclude_cn_from_sans = true
}

# Complete CSR in place by importing a single certificate to avoid keyless issuer creation.
resource "vault_pki_secret_backend_intermediate_set_signed" "pki_issuer_set" {
  provider    = vault.production
  backend     = vault_mount.pki_issuer.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.pki_issuer_signed.certificate
}

data "vault_pki_secret_backend_issuers" "pki_issuer_issuers" {
  provider   = vault.production
  backend    = vault_mount.pki_issuer.path
  depends_on = [vault_pki_secret_backend_intermediate_set_signed.pki_issuer_set]
}

locals {
  issuer_key_bearing_issuer_ids = [
    for issuer_id, key_id in data.vault_pki_secret_backend_issuers.pki_issuer_issuers.key_info :
    issuer_id if key_id != ""
  ]
}

resource "vault_pki_secret_backend_config_issuers" "pki_issuer_default" {
  provider                      = vault.production
  backend                       = vault_mount.pki_issuer.path
  default                       = local.issuer_key_bearing_issuer_ids[0]
  default_follows_latest_issuer = true

  lifecycle {
    precondition {
      condition     = length(local.issuer_key_bearing_issuer_ids) > 0
      error_message = "The pki_issuer mount does not contain any key-bearing issuers. The set-signed import operation may fail, or all certificates may be imported as keyless issuers."
    }
  }
}

# CRL and OCSP configuration URLs
resource "vault_pki_secret_backend_config_urls" "pki_issuer_urls" {
  provider = vault.production
  backend  = vault_mount.pki_issuer.path

  issuing_certificates    = ["${local.pki_api_base_url}/ca"]
  crl_distribution_points = ["${local.pki_api_base_url}/crl"]
}

# Unified PKI role definitions
resource "vault_pki_secret_backend_role" "pki_leaf_roles" {
  provider = vault.production
  for_each = var.pki_roles

  backend         = vault_mount.pki_issuer.path
  name            = each.value.name
  allowed_domains = each.value.allowed_domains

  allow_subdomains   = true
  allow_glob_domains = false
  allow_ip_sans      = true
  allow_bare_domains = true
  require_cn         = true

  key_usage = ["DigitalSignature", "KeyEncipherment", "KeyAgreement"]

  server_flag = true
  client_flag = true

  max_ttl = each.value.max_ttl
  ttl     = each.value.ttl

  ou = each.value.ou

  allow_any_name    = false
  enforce_hostnames = true
}

# 1. Shared AppRole authentication backend for workload identity
resource "vault_auth_backend" "approle" {
  provider = vault.production
  path     = "workload-approle"
  type     = "approle"
}

# 2. Isolated Kubernetes authentication backends for cluster identity isolation
resource "vault_auth_backend" "kubernetes" {
  provider = vault.production
  for_each = toset(distinct([for k, v in var.pki_roles : v.auth_path if v.auth_method == "kubernetes"]))

  path = each.value
  type = "kubernetes"
}

# Unified PKI policies for certificate signing and issuance
resource "vault_policy" "pki_policies" {
  provider = vault.production
  for_each = var.pki_roles

  name = "${each.value.name}-pki-policy"

  policy = jsonencode({
    path = {
      "${vault_mount.pki_issuer.path}/sign/${each.value.name}" = {
        capabilities = ["create", "update"]
      }
      "${vault_mount.pki_issuer.path}/issue/${each.value.name}" = {
        capabilities = ["create", "update"]
      }
      "${vault_mount.pki_issuer.path}/crl" = {
        capabilities = ["read"]
      }
    }
  })
}
