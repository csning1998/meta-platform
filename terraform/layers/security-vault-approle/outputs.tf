
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
  value       = vault_mount.pki_int.path
}

output "production_vault_endpoint" {
  description = "The address of the production Vault server."
  value       = local.production_vault_endpoint
}

output "trust_bundle_path" {
  description = "Absolute path to the combined CA trust bundle, for manual import into a local OS/browser trust store."
  value       = abspath(local_file.trust_bundle.filename)
}
