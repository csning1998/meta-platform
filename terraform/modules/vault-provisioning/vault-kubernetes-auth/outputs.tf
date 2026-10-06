
# The identity output depends on constants alone. Helm templates which read the identity therefore render during plan.
output "kubernetes_identity" {
  description = "Kubernetes names of the identities which log in to Vault, and the ClusterIssuer reference for Certificate resources."
  value = merge(local.identity, {
    cluster_issuer_ref = {
      group = "cert-manager.io"
      kind  = "ClusterIssuer"
      name  = local.identity.cluster_issuer_name
    }
  })
}

output "cluster_issuer" {
  description = "Coordinates of the cert-manager ClusterIssuer: its name, its token ServiceAccount, its Vault Kubernetes auth mount and role, and the PKI path against which it signs. The fields match the issuer_config input of platform-cluster-issuer."
  value = {
    name            = local.identity.cluster_issuer_name
    namespace       = local.identity.cert_manager_namespace
    service_account = local.identity.cluster_issuer_service_account
    issue_path      = local.pki_action_path
    pki_mount_path  = var.pki_config.mount_path
    auth_path       = vault_auth_backend.kubernetes.path
    vault_role_name = vault_kubernetes_auth_backend_role.cluster_issuer.role_name
  }
}

output "external_secrets" {
  description = "Coordinates of the External Secrets Operator: its ServiceAccount, its Vault Kubernetes auth mount and role, and the KV paths which it reads. Null when external_secrets_config is null."
  value = var.external_secrets_config == null ? null : {
    namespace       = local.identity.external_secrets_namespace
    service_account = local.identity.external_secrets_service_account
    auth_path       = vault_auth_backend.kubernetes.path
    role_name       = vault_kubernetes_auth_backend_role.external_secrets[0].role_name
    kv_mount_path   = var.external_secrets_config.kv_mount_path
    kv_paths        = var.external_secrets_config.kv_paths
  }
}
