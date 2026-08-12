
# Configure production Issuing Intermediate, per-service PKI roles, and AppRole authentication.
# Generates and retains the private key locally within production Vault; transmits only the CSR
# to Bootstrap Vault for signing.
module "vault_pki_setup" {
  source = "../../modules/vault-provisioning/vault-pki-setup"
  providers = {
    vault.production = vault.production
    vault.bootstrap  = vault.bootstrap
  }

  prod_vault_endpoint = local.prod_vault_endpoint
  pki_settings = {
    intermediate_ca_common_name = local.global_pki_config.intermediate_ca_common_name
  }
  pki_roles = local.pki_roles
  pki_engine_config = {
    path                      = local.prod_pki_issuer_mount_path
    default_lease_ttl_seconds = local.pki_lease_ttl_seconds
    max_lease_ttl_seconds     = local.pki_lease_ttl_seconds
  }
  bastion_pki_inter_mount_path = local.state.bootstrapper.bastion_pki_inter_mount_path
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
  pki_mount_path     = module.vault_pki_setup.prod_pki_issuer_mount_path
  extra_policy_hcl   = lookup(local.workload_identity_extra_rules, each.key, {})
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
    chomp(local.bastion_pki_chain_pem),
    chomp(base64decode(module.vault_pki_setup.prod_pki_issuer_cert_b64)),
  ])
  filename = "${path.module}/tls/trust-bundle.crt"
}
