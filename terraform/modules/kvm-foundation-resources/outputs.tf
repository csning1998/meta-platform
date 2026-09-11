
output "infrastructure_map" {
  description = "Physical realization bridging foundation-metadata Math and service VIPs, mapped perfectly to O(1) SSoT Identity keys. Consumed by all platform-*-frontend and provision-* layers."

  value = {
    for seg in local.net_service_segments : seg.name => {
      # 1. Physical Infrastructure (Libvirt bridges, IPs)
      network = local.net_infrastructure[seg.name]

      lb_config = {
        vip   = seg.vip
        ports = seg.ports
        tags  = seg.tags
      }

      # Runtime enum from service_catalog (baremetal, docker, podman, microk8s, kubeadm, minikube, talos, external),
      # This is read by provision-cilium-frontend and platform-haproxy-frontend to decide which of the two owns a segment VIP.
      runtime = seg.runtime

      # 3. Available Node IP slots for downstream consumption
      backend_servers = seg.backend_servers
    }
  }
}

output "service_segments" {
  description = "Stable map of service segments, consumed by platform-cilium-frontend for network identity outputs."
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

output "ssh_hosts" {
  description = "sshclient_identity_key/sshclient_host_config input map, keyed by cluster_name. Passed directly as the hosts variable of the ssh-identity-bootstrap module."
  value       = local.ssh_hosts
}

output "ssh_credential_paths" {
  description = "Vault KV path per cluster_name for the generated SSH identity key material. foundation-vault-bastion writes ssh_private_key/ssh_public_key under this path."
  value       = local.ssh_credential_paths
}

output "global_credential_paths" {
  description = "Mount-relative Vault KV paths for all service component credentials, nested by service and component."
  value       = module.service_catalog.credential_paths
}
