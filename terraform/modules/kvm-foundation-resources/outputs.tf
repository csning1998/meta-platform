
output "infrastructure_map" {
  description = "Physical realization bridging foundation-metadata Math and HAProxy VIPs, mapped perfectly to O(1) SSoT Identity keys. Consumed by all shared-*-frontend and provision-* layers."

  value = {
    for seg in local.net_service_segments : seg.name => {
      # 1. Physical Infrastructure (Libvirt bridges, IPs)
      network = local.net_infrastructure[seg.name]

      # 2. HAProxy / Keepalived Details
      lb_config = {
        vip            = seg.vip
        vrid           = seg.vrid
        interface_name = seg.interface_name
        ports          = seg.ports
        tags           = seg.tags
      }

      # 3. Available Node IP slots for downstream consumption
      backend_servers = seg.backend_servers
    }
  }
}

output "central_lb_info" {
  description = "Physical network configuration for the Central LB's own segment."
  value = merge(
    local.net_infrastructure[local.central_lb_key],
    {
      ports = local.segments[local.central_lb_key].network.ports
    }
  )
}

output "service_segments" {
  description = "Stable map of service segments, consumed by shared-load-balancer-frontend for HAProxy and Keepalived configuration."
  value       = local.net_service_segments
}

output "dns_mapping" {
  description = "SSoT DNS mapping for verification of Grouping and Sorting logic."
  value = [
    for ip in sort(distinct([for r in local.metadata.global_dns_records : r.ip])) : {
      ip        = ip
      hostnames = sort(distinct([for r in local.metadata.global_dns_records : r.hostname if r.ip == ip]))
    }
  ]
}

output "storage_infrastructure_map" {
  description = "Physical realization of the global volume map. Ready to be plugged into KVM instances."
  value       = local.global_volume_map
}

output "global_domain_suffix" {
  description = "The root domain suffix (e.g., iac.local) for all downstream consumer projects."
  value       = var.domain_suffix
}

output "global_pki_config" {
  description = "Global PKI identity settings for downstream layers (e.g. Vault PKI)."
  value       = var.pki_config
}

output "global_network_baseline" {
  description = "Base network configuration including CIDR, VIP offsets, and global MTU/MSS settings."
  value       = var.network_baseline
}

output "global_topology_network" {
  description = "Granular network attributes for all services/components (IPs, MACs, VIPs)."
  value       = module.service_catalog.topology_network
}

output "global_topology_identity" {
  description = "Granular cluster/node/storage identity and naming attributes."
  value       = module.service_catalog.topology_identity
}

output "global_volume_map" {
  description = "Pure MECE mapping of calculated storage volume attributes (Pools and physical Data Disks)."
  value       = module.service_catalog.volume_map
}

output "global_pki_map" {
  description = "Pure mapping of DNS SANs and organizational context for certificate generation."
  value       = module.service_catalog.pki_map
}

output "global_dns_records" {
  description = "SSoT mapping of all infrastructure hostnames to their respective VIPs."
  value       = module.service_catalog.dns_records
}

output "global_credential_paths" {
  description = "Mount-relative Vault KV paths for all service component credentials, nested by service and component."
  value       = module.service_catalog.credential_paths
}
