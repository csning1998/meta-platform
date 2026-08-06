
output "topology_network" {
  description = "Granular network attributes for all services/components (IPs, MACs, VIPs), nested by service and component."
  value = {
    for s_name, s in var.service_catalog : s_name => {
      for c_name, c in s.components : c_name => local.network_topology["${s_name}-${c_name}"]
    }
  }
}

output "topology_identity" {
  description = "Granular cluster/node/storage identity and naming attributes, nested by service and component."
  value = {
    for s_name, s in var.service_catalog : s_name => {
      for c_name, c in s.components : c_name => local.identity_map["${s_name}-${c_name}"]
    }
  }
}

output "volume_map" {
  description = "Flat mapping of calculated storage volume attributes (pools and physical data disks)."
  value       = local.volume_topology
}

output "pki_map" {
  description = "Flat mapping of DNS SANs and organizational context for certificate generation."
  value       = local.pki_map
}

output "dns_records" {
  description = "Mapping of all component hostnames to their respective VIPs."
  value       = local.dns_records
}
