
output "downstream_tenants" {
  description = "Downstream Vault connection parameters, the SPIRE Parent JWT auth backend, and the login coordinates of every tenant workload on the Parent or the Child mount."
  value = {
    endpoint     = local.downstream_vault.endpoint
    ca_cert_path = local.downstream_vault.ca_cert_path
    auth_mount   = local.jwt_auth.parent.mount_path
    audience     = local.jwt_auth.parent.audience
    kv_mount     = vault_mount.kv.path
    tenant_operator = {
      auth_mount = local.jwt_auth.parent.mount_path
      role_name  = vault_jwt_auth_backend_role.operator.role_name
      audience   = local.jwt_auth.parent.audience
    }
    role_spiffe_id = { for name, t in var.tenants : name => t.spiffe_id }
    tenant_login = {
      for name, t in var.tenants : name => {
        auth_mount = t.issuer == "parent" ? local.jwt_auth.parent.mount_path : local.spire_child_jwt_auth.mount_path
        role_name  = name
        audience   = t.issuer == "parent" ? local.jwt_auth.parent.audience : local.spire_child_jwt_auth.audience
      }
    }
  }
}

output "downstream_vault_service_vip" {
  description = "Service VIP of downstream Vault cluster retrieved from platform state."
  value       = local.state.platform_vault_downstream_frontend.vault_endpoint.service_vip
}

output "downstream_vault_endpoint" {
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

output "downstream_vault_ca_cert_path" {
  description = "Filesystem path to the CA certificate bundle validating downstream Vault listener TLS."
  value       = local.downstream_vault.ca_cert_path
}

output "downstream_vault_tenant_operator" {
  description = "Login coordinates of the administrator operator of the Downstream Vault, which only the vault-downstream SPIFFE ID assumes."
  value = {
    auth_mount   = local.jwt_auth.parent.mount_path
    role_name    = vault_jwt_auth_backend_role.operator.role_name
    audience     = local.jwt_auth.parent.audience
    wrapper_name = local.tenant_operator.wrapper_name
  }
}

output "downstream_vault_component_operators" {
  description = "Login coordinates of the operator of each component, keyed as the terraform_operator output of provision-spire-parent: the auth mount, the role, the audience, the JWT-SVID wrapper, the cluster name, and the workload policies which the operator assigns on its Kubernetes auth mount."
  value = {
    for key, operator in local.component_operators : key => {
      auth_mount   = local.jwt_auth.parent.mount_path
      role_name    = vault_jwt_auth_backend_role.component_operator[key].role_name
      audience     = local.jwt_auth.parent.audience
      wrapper_name = operator.wrapper_name
      cluster_name = operator.cluster_name
      # The workload policies which this layer declares for the cluster, null when the component has none.
      cluster_issuer_policy   = contains(keys(local.workload_policies), "${operator.cluster_name}-cluster-issuer") ? vault_policy.workload["${operator.cluster_name}-cluster-issuer"].name : null
      external_secrets_policy = contains(keys(local.workload_policies), "${operator.cluster_name}-external-secrets") ? vault_policy.workload["${operator.cluster_name}-external-secrets"].name : null
    }
  }
}

output "spire_child_jwt_auth" {
  description = "Mount path and audience of the JWT backend of the SPIRE Child on the Downstream Vault, which provision-spire-child creates, and the tenants whose roles the backend carries with the policy of the same name."
  value = {
    mount_path = local.spire_child_jwt_auth.mount_path
    audience   = local.spire_child_jwt_auth.audience
    tenants    = { for name, t in local.child_tenants : name => { spiffe_id = t.spiffe_id, policy_name = vault_policy.tenant[name].name } }
  }
}
