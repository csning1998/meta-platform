
output "kubeconfig_raw" {
  description = "Raw kubeconfig for the Kubernetes cluster, retrieved only after cluster health checks converge."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "client_configuration" {
  description = "Sensitive Talos client credentials comprising CA certificate, client certificate, and private key."
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}

output "hostonly_addresses" {
  description = "Per-node static HostOnly interface IP addresses."
  value       = local.hostonly_addresses
}

output "bootstrap_node_key" {
  description = "Target node identifier for etcd cluster bootstrap and Kubernetes API endpoint initialization."
  value       = local.bootstrap_node_key
}
