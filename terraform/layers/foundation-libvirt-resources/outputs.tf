
output "infrastructure_map" {
  description = "Physical realization bridging topology identity and HAProxy VIPs, mapped perfectly to O(1) SSoT Identity keys. Consumed by all platform-*-frontend and provision-* layers."
  value       = module.foundation_libvirt_resources.infrastructure_map
}

output "central_lb_info" {
  description = "Physical network configuration for the Central LB's own segment."
  value       = module.foundation_libvirt_resources.central_lb_info
}

output "service_segments" {
  description = "Stable map of service segments, consumed by platform-load-balancer-frontend for HAProxy and Keepalived configuration."
  value       = module.foundation_libvirt_resources.service_segments
}

output "dns_mapping" {
  description = "SSoT DNS mapping for verification of Grouping and Sorting logic."
  value       = module.foundation_libvirt_resources.dns_mapping
}

output "storage_infrastructure_map" {
  description = "Physical realization of the global volume map. Ready to be plugged into KVM instances."
  value       = module.foundation_libvirt_resources.storage_infrastructure_map
}

output "global_topology_identity" {
  description = "Topology identity map; consumed by platform-load-balancer-frontend to build segments_map."
  value       = module.foundation_libvirt_resources.global_topology_identity
}

output "global_topology_network" {
  description = "Topology network map; consumed by platform-load-balancer-frontend to build segments_map."
  value       = module.foundation_libvirt_resources.global_topology_network
}

output "global_network_baseline" {
  description = "Global network baseline (global_mtu, global_mss); consumed by platform-load-balancer-frontend for Ansible extra vars."
  value       = module.foundation_libvirt_resources.global_network_baseline
}

output "global_domain_suffix" {
  description = "Root domain suffix; consumed by platform-load-balancer-frontend for Ansible template service_domain."
  value       = module.foundation_libvirt_resources.global_domain_suffix
}

output "global_pki_config" {
  description = "Global PKI identity settings for downstream layers (e.g. Vault PKI)."
  value       = module.foundation_libvirt_resources.global_pki_config
}

output "global_volume_map" {
  description = "Pure MECE mapping of calculated storage volume attributes (Pools and physical Data Disks)."
  value       = module.foundation_libvirt_resources.global_volume_map
}

output "global_pki_map" {
  description = "Pure mapping of DNS SANs and organizational context for certificate generation."
  value       = module.foundation_libvirt_resources.global_pki_map
}

output "global_dns_records" {
  description = "SSoT mapping of all infrastructure hostnames to their respective VIPs."
  value       = module.foundation_libvirt_resources.global_dns_records
}

output "vault_kv_namespace" {
  description = "Pass-through of the Vault KV mount-relative namespace prefix; consumed by security-vault-approle for credential path construction without reading this layer directly."
  value       = var.vault_kv_namespace
}

output "global_credential_paths" {
  description = "Mount-relative Vault KV paths for all service component credentials, derived from the service catalog."
  value       = module.foundation_libvirt_resources.global_credential_paths
}
