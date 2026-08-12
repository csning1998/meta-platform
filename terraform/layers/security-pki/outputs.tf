
output "pki_mount_path" {
  description = "Mount path of the Production Issuing Intermediate PKI engine."
  value       = module.vault_pki_setup.vault_pki_path
}

output "trust_bundle_path" {
  description = "Absolute path to the combined CA trust bundle, for manual import into a local OS/browser trust store."
  value       = abspath(local_file.trust_bundle.filename)
}

output "pki_intermediate_ca_certificate_b64" {
  description = "Base64-encoded, signed Production Issuing Intermediate CA certificate only, for server-served TLS chains (excludes the Root CA)."
  value       = module.vault_pki_setup.pki_intermediate_ca_certificate_b64
}

output "bootstrap_ca_b64" {
  description = "Export CA trust bundle file path and Base64-encoded string representation for inline consumption."
  value = {
    path        = abspath(local_file.trust_bundle.filename)
    content_b64 = base64encode(local_file.trust_bundle.content)
  }
}

output "pki_configuration" {
  description = "Export production PKI mount point, TTL lease profiles, and service role mappings."
  value = {
    path      = module.vault_pki_setup.vault_pki_path
    pki_roles = module.vault_pki_setup.pki_roles
    lease_durations = {
      default = "${local.pki_lease_ttl_seconds / 3600}h"
      max     = "${local.pki_lease_ttl_seconds / 3600}h"
      agent   = var.vault_agent_lease_ttl
    }
  }
}

output "management_policies" {
  description = "Map of human management identities (oidc-admin, oidc-auditor, oidc-developer) to their generated Vault ACL policy names, for OIDC group-to-policy mapping."
  value       = { for k in local.management_identities : k => module.vault_workload_identity_approle[k].policy_name }
}

output "workload_identities_approle" {
  description = "Export workload AppRole authentication parameters indexed by service name."
  sensitive   = true
  value = {
    for service_name, mod in module.vault_workload_identity_approle : service_name => {
      role_id   = mod.approle_role_id
      role_name = mod.approle_name
      auth_path = module.vault_pki_setup.auth_backend_paths["approle"]
    }
  }
}
