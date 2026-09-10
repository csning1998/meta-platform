
output "infrastructure_map" {
  description = "Physical realization bridging topology identity and service VIPs, mapped perfectly to O(1) SSoT Identity keys. Consumed by all platform-*-frontend and provision-* layers."
  value       = module.foundation_libvirt_resources.infrastructure_map
}

output "service_segments" {
  description = "Stable map of service segments, consumed by platform-cilium-frontend for network identity outputs."
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
  description = "Topology identity map; consumed by platform-cilium-frontend to build segments_map."
  value       = module.foundation_libvirt_resources.global_topology_identity
}

output "global_topology_network" {
  description = "Topology network map; consumed by platform-cilium-frontend to build segments_map."
  value       = module.foundation_libvirt_resources.global_topology_network
}

output "global_network_baseline" {
  description = "Global network baseline (global_mtu, global_mss); consumed by platform-cilium-frontend for Ansible extra vars."
  value       = module.foundation_libvirt_resources.global_network_baseline
}

output "global_domain_suffix" {
  description = "Root domain suffix; consumed by platform-cilium-frontend for Ansible template service_domain."
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

output "ssh_identity_key_paths" {
  description = "Written private key path per cluster_name; consumed by each ha-service-kvm-general instance as its credentials_system.ssh_private_key_path."
  value       = module.ssh_identity_bootstrap.identity_key_private_paths
}

output "ssh_public_key_paths" {
  description = "Written public key path per cluster_name; consumed by each ha-service-kvm-general instance as its credentials_system.ssh_public_key_path, and by foundation-vault-bastion for the Vault upload."
  value       = module.ssh_identity_bootstrap.identity_key_public_paths
}

output "ssh_config_paths" {
  description = "Written ssh_config Host block path per cluster_name."
  value       = module.ssh_identity_bootstrap.host_config_paths
}

output "ssh_known_hosts_paths" {
  description = "known_hosts path this layer assumed for known_hosts_file, keyed by cluster_name. ha-service-kvm-general's own sshclient_known_host call MUST use the same cluster_name so the two layers resolve the same path."
  value       = module.ssh_identity_bootstrap.known_hosts_paths
}

output "ssh_credential_paths" {
  description = "Vault KV path per cluster_name for the generated SSH identity key material; consumed by foundation-vault-bastion."
  value       = module.foundation_libvirt_resources.ssh_credential_paths
}
