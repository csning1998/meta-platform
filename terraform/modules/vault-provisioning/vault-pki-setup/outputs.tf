
output "prod_pki_issuer_mount_path" {
  description = "The path where PKI engine is mounted"
  value       = vault_mount.pki_issuer.path
}

output "prod_pki_issuer_cert_b64" {
  description = "The signed Issuer certificate in Base64"
  value       = base64encode(vault_pki_secret_backend_root_sign_intermediate.pki_issuer_signed.certificate)
}

output "prod_pki_leaf_roles" {
  description = "Map of provisioned PKI Roles with encapsulated attributes"
  value = {
    for k, v in vault_pki_secret_backend_role.pki_leaf_roles : k => {
      id              = v.id
      name            = v.name
      allowed_domains = v.allowed_domains
    }
  }
}

output "auth_backend_paths" {
  description = "Map of enabled Auth Backend paths"
  value = merge(
    { "approle" = vault_auth_backend.approle.path },
    { for k, v in vault_auth_backend.kubernetes : k => v.path }
  )
}
