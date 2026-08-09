
# A Vault instance rebuilt from an empty raft store provides no default KV mount.
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

path "pki_int/issue/*" {
  capabilities = ["create", "update"]
}

path "sys/mounts/pki_int" {
  capabilities = ["read"]
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

# Production Issuing Intermediate. The CSR is generated and its key retained inside the
# production Vault; only the CSR itself crosses to the Bootstrap Vault for signing, mirroring
# foundation-vault-bastion's own root-to-intermediate flow one tier down.
resource "vault_mount" "pki_int" {
  provider    = vault.production
  path        = "pki_int"
  type        = "pki"
  description = "Production Issuing Intermediate, signed by the Bootstrap Issuing Intermediate."

  default_lease_ttl_seconds = 60 * 60 * 24 * 365
  max_lease_ttl_seconds     = 60 * 60 * 24 * 365
}

resource "vault_pki_secret_backend_intermediate_cert_request" "production_int_csr" {
  provider = vault.production
  backend  = vault_mount.pki_int.path

  type        = "internal"
  common_name = "meta-platform Production Intermediate CA"
  key_type    = "rsa"
  key_bits    = 4096
}

resource "vault_pki_secret_backend_root_sign_intermediate" "production_int_signed" {
  provider = vault.bastion
  backend  = local.state.bootstrapper.bootstrap_pki_mount_path

  csr                  = vault_pki_secret_backend_intermediate_cert_request.production_int_csr.csr
  common_name          = "meta-platform Production Intermediate CA"
  format               = "pem"
  ttl                  = 60 * 60 * 24 * 365
  exclude_cn_from_sans = true
}

# Importing only the certificate lets Vault match it back to the key generated above by
# public key, avoiding a keyless issuer.
resource "vault_pki_secret_backend_intermediate_set_signed" "production_int_set" {
  provider    = vault.production
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.production_int_signed.certificate
}

resource "vault_pki_secret_backend_config_issuers" "production_int_default" {
  provider                      = vault.production
  backend                       = vault_mount.pki_int.path
  default                       = vault_pki_secret_backend_intermediate_set_signed.production_int_set.imported_issuers[0]
  default_follows_latest_issuer = true
}

# Listener CA (`MetaProvisionVaultCA`) for Bastion Vault TLS endpoints. Distinct from PKI secrets engine roots.
data "local_file" "bastion_listener_ca" {
  filename = abspath("${path.root}/../../../vault/tls/ca.pem")
}

# Combined certificate chain (Bastion Listener CA, Bootstrap Root/Intermediate, Production Intermediate)
# for local trust store installation. Requires manual import; not managed by system trust utilities.
resource "local_file" "trust_bundle" {
  content = join("\n", [
    chomp(data.local_file.bastion_listener_ca.content),
    chomp(local.bootstrap_ca_chain_pem),
    chomp(vault_pki_secret_backend_root_sign_intermediate.production_int_signed.certificate),
  ])
  filename = "${path.module}/tls/trust-bundle.crt"
}
