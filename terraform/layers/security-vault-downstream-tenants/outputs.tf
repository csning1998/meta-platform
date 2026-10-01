
output "downstream_tenants" {
  description = "Downstream Vault connection parameters, JWT auth backends, and role bindings for tenant workloads."
  value = {
    endpoint     = local.downstream_vault.endpoint
    ca_cert_path = local.downstream_vault.ca_cert_path
    auth_mount   = vault_jwt_auth_backend.spire_child.path
    audience     = local.jwt_auth.child.audience
    kv_mount     = vault_mount.kv.path
    tenant_operator = {
      auth_mount = vault_jwt_auth_backend.spire_child.path
      role_name  = vault_jwt_auth_backend_role.operator.role_name
      audience   = local.jwt_auth.child.audience
    }
    role_spiffe_id = { for name, role in vault_jwt_auth_backend_role.tenant : name => role.bound_subject }
    tenant_login = {
      for name, t in var.tenants : name => {
        auth_mount = local.jwt_auth[t.issuer].mount_path
        role_name  = vault_jwt_auth_backend_role.tenant[name].role_name
        audience   = local.jwt_auth[t.issuer].audience
      }
    }
  }
}

output "service_vip" {
  description = "Service VIP of downstream Vault cluster retrieved from platform state."
  value       = local.state.platform_vault_downstream_frontend.service_vip
}

output "endpoint" {
  description = "Downstream Vault API endpoint URL."
  value       = local.downstream_vault.endpoint
}

output "foundation_pki" {
  description = "Pass-through of foundation PKI configuration for downstream TLS verification."
  value       = local.state.foundation_libvirt_resources.foundation_pki
}

output "foundation_vault_path" {
  description = "Pass-through of foundation Vault KV secret paths for consumer layers."
  value       = local.state.foundation_libvirt_resources.foundation_vault_path
}

output "ca_cert_path" {
  description = "Filesystem path to the CA certificate bundle validating downstream Vault listener TLS."
  value       = local.downstream_vault.ca_cert_path
}

output "tenant_operator" {
  description = "Authentication coordinates for workstation Terraform operators accessing downstream Vault."
  value = {
    auth_mount = vault_jwt_auth_backend.spire_child.path
    role_name  = vault_jwt_auth_backend_role.operator.role_name
    audience   = local.jwt_auth.child.audience
  }
}
