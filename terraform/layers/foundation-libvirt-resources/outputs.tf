
output "foundation_topology" {
  description = "Topology of every service segment: identity, network, service segments, and the physical realization that bridges identity and service VIPs, all keyed by the SSoT identity."
  value = {
    identity       = module.foundation_libvirt_resources.global_topology_identity
    network        = module.foundation_libvirt_resources.global_topology_network
    segments       = module.foundation_libvirt_resources.service_segments
    infrastructure = module.foundation_libvirt_resources.infrastructure_map
  }
}

output "foundation_global" {
  description = "Global facts shared by every consumer: network baseline, root domain suffix, and the hostname to VIP records."
  value = {
    network_baseline = module.foundation_libvirt_resources.global_network_baseline
    domain_suffix    = module.foundation_libvirt_resources.global_domain_suffix
    dns_records      = module.foundation_libvirt_resources.global_dns_records
    dns_mapping      = module.foundation_libvirt_resources.dns_mapping
  }
}

output "foundation_pki" {
  description = "PKI facts derived from the service catalog: the global PKI identity settings, and the DNS SANs and organizational context per certificate."
  value = {
    config = module.foundation_libvirt_resources.global_pki_config
    map    = module.foundation_libvirt_resources.global_pki_map
  }
}

output "foundation_storage" {
  description = "Physical realization of the storage layout: the pools and data disks, and the calculated volume attributes."
  value = {
    infrastructure = module.foundation_libvirt_resources.storage_infrastructure_map
    volume_map     = module.foundation_libvirt_resources.global_volume_map
  }
}

output "foundation_vault_path" {
  description = "Vault KV coordinates of the service catalog: the first path segment shared by every service, the credential path of each component, and the path of each generated SSH identity."
  value = {
    kv_namespace         = one(distinct([for s in var.service_catalog : s.project_code]))
    credential_paths     = module.foundation_libvirt_resources.global_credential_paths
    ssh_credential_paths = module.foundation_libvirt_resources.ssh_credential_paths
  }
}

output "foundation_ssh" {
  description = "Local file paths of the SSH client material written by this layer, keyed by cluster_name. The known_hosts path is shared with the ha-service-kvm-general instance of the same cluster_name."
  value = {
    identity_key_paths = module.ssh_identity_bootstrap.identity_key_private_paths
    public_key_paths   = module.ssh_identity_bootstrap.identity_key_public_paths
    config_paths       = module.ssh_identity_bootstrap.host_config_paths
    known_hosts_paths  = module.ssh_identity_bootstrap.known_hosts_paths
  }
}
