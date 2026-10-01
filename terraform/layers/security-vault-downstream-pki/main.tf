
# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item C.
# Configure Downstream Issuing Intermediate and the PKI roles of the workloads which use the Downstream PKI.
# Generates and retains the private key locally within Downstream Vault; transmits only the CSR
# to Bootstrap Vault for signing.
module "vault_pki_setup" {
  source = "../../modules/vault-provisioning/vault-pki-setup"
  providers = {
    vault.issuing = vault.downstream
    vault.signing = vault.bastion
  }

  prod_vault_endpoint = local.downstream_vault.endpoint
  pki_settings = {
    intermediate_ca_common_name = local.state.platform_vault_downstream_frontend.pki_identity.intermediate_ca_common_name
  }
  pki_roles = local.pki_roles
  pki_engine_config = {
    path                      = local.downstream_vault.pki_mount_path
    default_lease_ttl_seconds = local.pki_lease_ttl_seconds
    max_lease_ttl_seconds     = local.pki_lease_ttl_seconds
  }
  bastion_pki_inter_mount_path = local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_mount_path
}

# The ACL policies of the human management identities. The policy name equals the identity name.
# provision-vault-oidc maps each OIDC group to the policy of the identity. Workloads on VMs and in Kubernetes log in
# with a JWT-SVID through the tenant registry of security-vault-downstream-tenants.
resource "vault_policy" "management" {
  provider = vault.downstream
  for_each = local.management_identities

  name = each.key
  policy = jsonencode({
    path = merge(
      {
        "${module.vault_pki_setup.prod_pki_issuer_mount_path}/issue/${local.pki_roles[each.key].name}" = {
          capabilities = ["create", "update"]
        }
      },
      local.workload_identity_extra_rules[each.key]
    )
  })
}

# Listener CA (`MetaProvisionVaultCA`) for Bastion Vault TLS endpoints. Distinct from PKI secrets engine roots.
data "local_file" "bastion_listener_ca" {
  filename = local.state.foundation_vault_bastion.bastion_vault.listener_ca_cert_path
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
