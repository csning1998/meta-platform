
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

output "prod_vault_endpoint" {
  description = "The address of the production Vault server."
  value       = local.prod_vault_endpoint
}

output "prod_vault_svc_vip" {
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
