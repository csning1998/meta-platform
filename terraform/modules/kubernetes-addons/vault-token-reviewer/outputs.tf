
output "vault_auth_path" {
  description = "Mount path of the Vault Kubernetes auth backend, which this module connects to the API server of the cluster."
  value       = vault_kubernetes_auth_backend_config.config.backend
}
