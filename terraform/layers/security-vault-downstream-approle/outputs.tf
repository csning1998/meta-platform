
output "role_id" {
  description = "The RoleID of the Downstream Terraform admin AppRole."
  value       = vault_approle_auth_backend_role.production_admin.role_id
}

output "secret_id" {
  description = "The SecretID of the Downstream Terraform admin AppRole."
  value       = vault_approle_auth_backend_role_secret_id.production_admin.secret_id
  sensitive   = true
}

output "approle_path" {
  description = "The path where AppRole auth is enabled on the Downstream Vault."
  value       = vault_auth_backend.approle.path
}

output "kv_mount_path" {
  description = "The path where the KV v2 secrets engine is enabled on the Downstream Vault."
  value       = vault_mount.kv.path
}

output "prod_vault_endpoint" {
  description = "The address of the Downstream Vault server."
  value       = local.prod_vault_endpoint
}

output "prod_vault_svc_vip" {
  description = "Export Downstream Vault Virtual IP address from `platform-vault-downstream-frontend` state for downstream consumed layers."
  value       = data.terraform_remote_state.vault_downstream.outputs.service_vip
}

output "foundation_pki" {
  description = "Pass-through of the foundation-libvirt-resources PKI object for downstream layer TLS configuration."
  value       = data.terraform_remote_state.foundation.outputs.foundation_pki
}

output "foundation_vault_path" {
  description = "Pass-through of the foundation-libvirt-resources Vault KV coordinates object for downstream path construction."
  value       = data.terraform_remote_state.foundation.outputs.foundation_vault_path
}
