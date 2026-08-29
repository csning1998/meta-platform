
# SSoT Output Alignment: Mirror foundation-metadata's former global_* output shape
# so the network/volume computation below reads a single consistent structure.
locals {
  metadata = {
    global_domain_suffix     = var.domain_suffix
    global_pki_config        = var.pki_config
    global_network_baseline  = var.network_baseline
    global_topology_network  = module.service_catalog.topology_network
    global_topology_identity = module.service_catalog.topology_identity
    global_volume_map        = module.service_catalog.volume_map
    global_pki_map           = module.service_catalog.pki_map
    global_dns_records       = module.service_catalog.dns_records
    global_credential_paths  = module.service_catalog.credential_paths
  }
}

# Network Map Reference: Zip Network Attributes with Identity Naming SSoT
locals {
  # 1. Zip the topological maps into a single manageable structure
  # Identity Map provides naming (Bridge, Pool, etc.), Network Map provides IPv4 attributes.
  # Use identity.cluster_name as the primary O(1) key for downstream realization.
  segments = merge([
    for s_name, components in local.metadata.global_topology_identity : {
      for c_name, identity in components : identity.cluster_name => {
        identity = identity
        network  = local.metadata.global_topology_network[s_name][c_name]
      }
    }
  ]...)
}

# Full Infrastructure Map (All Segments: Consumed by libvirt_network resources)
locals {
  net_infrastructure = {
    for key, data in local.segments : key => {
      hostonly = {
        name        = data.identity.cluster_name
        bridge_name = data.identity.bridge_name_host
        gateway     = cidrhost(data.network.cidr_block, 1)
        cidr        = data.network.cidr_block
        prefix      = 24
        mtu         = local.metadata.global_network_baseline.global_mtu
      }
      nat = {
        name        = "${data.identity.cluster_name}-nat"
        bridge_name = data.identity.bridge_name_nat
        gateway     = data.network.nat_gateway
        cidr        = data.network.nat_cidr_block
        prefix      = 24
        dhcp        = data.network.nat_dhcp
        mtu         = local.metadata.global_network_baseline.global_mtu
        stage       = data.identity.stage
      }
    }
  }
}

# Service Segments with at least one exposed port, used for Identity outputs.
locals {
  net_sorted_segment_keys = sort([
    for k, v in local.segments : k
    if length(v.network.ports) > 0
  ])

  net_service_segments = {
    for key in local.net_sorted_segment_keys : key => {
      name           = key
      bridge_name    = local.segments[key].identity.bridge_name_host
      cidr           = local.segments[key].network.cidr_block
      nat_cidr       = local.segments[key].network.nat_cidr_block
      nat_gateway    = local.segments[key].network.nat_gateway
      vrid           = local.segments[key].network.vrid
      vip            = local.segments[key].network.vip
      interface_name = local.segments[key].network.interface_alias
      ip_range       = local.segments[key].network.ip_range
      ports          = local.segments[key].network.ports
      tags           = local.segments[key].network.tags
      runtime        = local.segments[key].network.runtime
      mtu            = local.metadata.global_network_baseline.global_mtu
      mss            = local.metadata.global_network_baseline.global_mss

      # Use node_ips derived from foundation-metadata directly to avoid re-calculation
      backend_servers = [
        for idx, ip in local.segments[key].network.node_ips : {
          name = "${local.segments[key].identity.node_name_prefix}-${local.segments[key].network.ip_range.start_ip + idx}"
          ip   = ip
        }
      ]
    }
  }
}

# Global Infrastructure DNS SSoT (Requires Libvirt Provider >= 0.9.7)
locals {
  global_dns_hosts = [
    for ip in sort(distinct([for r in local.metadata.global_dns_records : r.ip])) : {
      ip = ip
      hostnames = [
        for h in sort(distinct([for r in local.metadata.global_dns_records : r.hostname if r.ip == ip])) : {
          hostname = h
        }
      ]
    }
  ]
}

# Volume Map Reference: Storage Pool and Data Disk realization from foundation-metadata SSoT.
locals {
  global_identity_map = merge([
    for s_name, components in local.metadata.global_topology_identity : {
      for c_name, identity in components : identity.cluster_name => identity
    }
  ]...)

  global_volume_map = local.metadata.global_volume_map

  # Extract unique pool names required for physical storage realization.
  # This includes pools for segments without data disks (root disk pools)
  # and specific data volume pools.
  unique_pools = toset(distinct(concat(
    [for key, identity in local.global_identity_map : identity.storage_pool_name],
    [for vol_key, vol_data in local.global_volume_map : vol_data.pool_name]
  )))
}

# Ensures storage pool names contain only alphanumeric characters, hyphens, and underscores
# to prevent path traversal outside /var/lib/libvirt/images during filesystem interpolation.
check "storage_pool_names_safe" {
  assert {
    condition     = alltrue([for name in local.unique_pools : can(regex("^[a-zA-Z0-9_-]+$", name))])
    error_message = "Storage pool names must contain only alphanumeric characters, hyphens, and underscores."
  }
}
