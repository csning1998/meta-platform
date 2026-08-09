
output "role_id" {
  description = "The RoleID of the production Terraform admin AppRole."
  value       = vault_approle_auth_backend_role.production_admin.role_id
}

output "secret_id" {
  description = "The SecretID of the production Terraform admin AppRole."
  value       = vault_approle_auth_backend_role_secret_id.production_admin.secret_id
  sensitive   = true
}

output "approle_path" {
  description = "The path where AppRole auth is enabled on the production Vault."
  value       = vault_auth_backend.approle.path
}

output "kv_mount_path" {
  description = "The path where the KV v2 secrets engine is enabled on the production Vault."
  value       = vault_mount.kv.path
}

output "pki_mount_path" {
  description = "Mount path of the Production Issuing Intermediate PKI engine."
  value       = module.vault_pki_setup.vault_pki_path
}

output "production_vault_endpoint" {
  description = "The address of the production Vault server."
  value       = local.production_vault_endpoint
}

output "trust_bundle_path" {
  description = "Absolute path to the combined CA trust bundle, for manual import into a local OS/browser trust store."
  value       = abspath(local_file.trust_bundle.filename)
}

output "vault_service_vip" {
  description = "Export production Vault Virtual IP address from `shared-vault-frontend` state for downstream consumed layers."
  value       = data.terraform_remote_state.vault_production.outputs.service_vip
}

output "global_pki_map" {
  description = "Export PKI role mapping schema (DNS SANs, role names, authentication settings) for downstream layer TLS configuration."
  value       = data.terraform_remote_state.foundation.outputs.global_pki_map
}

output "global_credential_paths" {
  description = "Export credential path mappings for downstream Vault KV path construction."
  value       = data.terraform_remote_state.foundation.outputs.global_credential_paths
}

output "vault_kv_namespace" {
  description = "Export Vault KV namespace prefix for downstream path resolution."
  value       = data.terraform_remote_state.foundation.outputs.vault_kv_namespace
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
