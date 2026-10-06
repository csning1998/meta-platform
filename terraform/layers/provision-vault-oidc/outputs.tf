
output "auth_oidc" {
  description = "Downstream Vault OIDC JWT authentication backend coordinates and login endpoint."
  value = {
    mount_path       = vault_jwt_auth_backend.keycloak.path
    backend_accessor = vault_jwt_auth_backend.keycloak.accessor
    role_name        = vault_jwt_auth_backend_role.keycloak_user.role_name
    login_url        = "${local.downstream_vault.fqdn}/ui/vault/auth/oidc"
  }
}
