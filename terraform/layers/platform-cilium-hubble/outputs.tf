
output "talos_cluster" {
  description = "Facts of the Cilium Hubble Talos cluster."
  value = {
    hostonly_addresses = module.establish_platform_cilium_hubble_talos_cluster.hostonly_addresses
    bootstrap_node_key = module.establish_platform_cilium_hubble_talos_cluster.bootstrap_node_key
    cluster_issuer     = module.vault_auth_cilium_hubble.cluster_issuer
    external_secrets   = module.vault_auth_cilium_hubble.external_secrets
  }
}

output "hubble_tls_certificates" {
  description = "Hubble mTLS certificates which the provision layer issues through the ClusterIssuer, keyed by the Secret name which the Cilium chart mounts."
  value       = module.helm_chart_cilium.hubble_tls_certificates
}
