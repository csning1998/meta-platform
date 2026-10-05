
output "hostonly_addresses" {
  description = "Static HostOnly interface addresses per Talos node."
  value       = module.platform_cilium_hubble.hostonly_addresses
}

output "bootstrap_node_key" {
  description = "The node key used as the etcd bootstrap and Kubernetes API endpoint target."
  value       = module.platform_cilium_hubble.bootstrap_node_key
}

output "cluster_issuer" {
  description = "Coordinates of the cert-manager ClusterIssuer against the Downstream Vault."
  value       = module.vault_auth_cilium_hubble.cluster_issuer
}

output "external_secrets" {
  description = "Coordinates of the External Secrets Operator against the Downstream Vault."
  value       = module.vault_auth_cilium_hubble.external_secrets
}

output "hubble_tls_certificates" {
  description = "Hubble mTLS certificates which the provision layer issues through the ClusterIssuer, keyed by the Secret name which the Cilium chart mounts."
  value       = module.helm_chart_cilium.hubble_tls_certificates
}
