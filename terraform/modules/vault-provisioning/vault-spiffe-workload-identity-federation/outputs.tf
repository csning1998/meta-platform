output "role_name" {
  description = "Name of the created JWT auth backend role."
  value       = vault_jwt_auth_backend_role.this.role_name
}
