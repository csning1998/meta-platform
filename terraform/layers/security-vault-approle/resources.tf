
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

# Configure production Issuing Intermediate, per-service PKI roles, and AppRole authentication.
# Generates and retains the private key locally within production Vault; transmits only the CSR
# to Bootstrap Vault for signing.
module "vault_pki_setup" {
  source = "../../modules/vault-provisioning/vault-pki-setup"
  providers = {
    vault.production = vault.production
    vault.bootstrap  = vault.bastion
  }

  vault_endpoint = local.production_vault_endpoint
  pki_settings   = data.terraform_remote_state.foundation.outputs.global_pki_config
  pki_roles      = local.pki_roles
  pki_engine_config = {
    path                      = "pki_int"
    default_lease_ttl_seconds = local.pki_lease_ttl_seconds
    max_lease_ttl_seconds     = local.pki_lease_ttl_seconds
  }
  bootstrap_pki_mount_path          = local.state.bootstrapper.bootstrap_pki_mount_path
  bootstrap_root_ca_certificate_pem = local.state.bootstrapper.bootstrap_root_ca_certificate_pem
}

# Provision individual workload AppRoles scoped to corresponding PKI roles defined in `global_pki_map`.
module "vault_workload_identity_approle" {
  source = "../../modules/vault-provisioning/vault-workload-identity"
  providers = {
    vault = vault.production
  }
  depends_on = [module.vault_pki_setup]

  for_each           = local.pki_roles
  name               = each.key
  vault_role_name    = each.value.name
  approle_mount_path = module.vault_pki_setup.auth_backend_paths["approle"]
  pki_mount_path     = module.vault_pki_setup.vault_pki_path
}

# Listener CA (`MetaProvisionVaultCA`) for Bastion Vault TLS endpoints. Distinct from PKI secrets engine roots.
data "local_file" "bastion_listener_ca" {
  filename = abspath("${path.root}/../../../vault/tls/ca.pem")
}

# Combined certificate chain (Bastion Listener CA, Bootstrap Root/Intermediate, Production Intermediate)
# for local trust store installation.
resource "local_file" "trust_bundle" {
  content = join("\n", [
    chomp(data.local_file.bastion_listener_ca.content),
    chomp(local.bootstrap_ca_chain_pem),
    chomp(base64decode(module.vault_pki_setup.pki_intermediate_ca_certificate_b64)),
  ])
  filename = "${path.module}/tls/trust-bundle.crt"
}
