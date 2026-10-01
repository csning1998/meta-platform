
output "cluster_issuer" {
  description = "ClusterIssuer identity and associated Secret coordinates for platform-cluster-issuer module."
  value = {
    name                   = var.issuer_config.name
    kind                   = "ClusterIssuer"
    token_secret_name      = kubernetes_secret_v1.issuer_token.metadata[0].name
    token_secret_namespace = kubernetes_secret_v1.issuer_token.metadata[0].namespace
  }
}

output "vault" {
  description = "Configured Vault Kubernetes auth backend mount and role identifier."
  value = {
    auth_path = var.vault_config.auth_path
    role_name = var.issuer_config.vault_role_name
  }
}
