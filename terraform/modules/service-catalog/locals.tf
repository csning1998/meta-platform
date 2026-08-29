
# service-catalog: Naming and Identity Topology

locals {
  # Flattened catalog, SSoT for per-component identity
  _flat_catalog = merge([
    for s_name, s in var.service_catalog : {
      for c_name, c in s.components : "${s_name}-${c_name}" => {
        service_name      = s_name
        comp_name         = c_name
        config            = c
        project           = s.project_code
        stage             = s.stage
        owner             = s.owner
        cluster_name      = "${s.project_code}-${s_name}-${c_name}"
        storage_pool_name = "${s.project_code}-${s_name}-${c_name}-pool"
        hash_prefix       = substr(md5("${s.project_code}-${s_name}-${c_name}"), 0, 8)
      }
    }
  ]...)

  # Component roles and DNS names
  component_roles = flatten([
    for key, item in local._flat_catalog : {
      key       = key
      role_name = "${item.cluster_name}-role"
      ttl_stage = item.stage

      has_ingress = length(coalesce(item.config.ingress, {})) > 0

      # DNS SAN list
      dns_san = distinct(concat(
        flatten([
          for i_key, i_data in coalesce(item.config.ingress, {}) : [
            for sub in i_data.subdomains :
            join(".", compact([
              sub,
              lookup({ (item.service_name) = "" }, sub, item.service_name),
              item.stage,
              var.domain_suffix
            ]))
          ]
        ]),
        item.comp_name == "frontend" ? ["${item.service_name}.${item.stage}.${var.domain_suffix}"] : [],
        ["${item.cluster_name}.${item.stage}.${var.domain_suffix}"]
      ))

      # Certificate subject OU fields
      ou = [
        "Provider=${item.config.provider}",
        "Env=${item.stage}",
        "Owner=${item.owner}",
        "Project=${item.project}",
        "Runtime=${item.config.runtime}",
        "Tag=${join(",", coalesce(item.config.tags, []))}"
      ]

      auth_config = {
        method       = contains(["kubeadm", "microk8s"], item.config.runtime) ? "kubernetes" : "approle"
        path         = contains(["kubeadm", "microk8s"], item.config.runtime) ? "kubernetes/${item.service_name}/${item.comp_name}" : "workload-approle"
        approle_path = "workload-approle"
      }

      oidc_client = item.config.oidc_client != null ? merge(item.config.oidc_client, {
        client_id = item.cluster_name
      }) : null
    }
  ])

  # Final PKI attribute mapping used by TLS/Vault layers
  pki_map = { for item in local.component_roles : item.key => item }

  # Identity map, SSoT for OS/hypervisor object naming
  identity_map = {
    for key, item in local._flat_catalog : key => {
      cluster_name      = item.cluster_name
      stage             = item.stage
      storage_pool_name = item.storage_pool_name
      bridge_name_host  = "vbr${item.hash_prefix}"
      bridge_name_nat   = "vbr${item.hash_prefix}-n"
      node_name_prefix  = "${item.cluster_name}-node"
      ansible_inventory = "inventory-${item.cluster_name}.yaml"
      ssh_config        = "ssh_${item.cluster_name}"

      # Per-group node naming
      groups = {
        for group in coalesce(item.config.node_groups, []) :
        group => {
          node_name_prefix = "${item.cluster_name}-${group}-node"
        }
      }
    }
  }
}

# service-catalog: Network Topology

locals {
  # Per-component CIDR, VIP, MAC, and node IP computation
  network_topology = {
    for key, item in local._flat_catalog : key => {
      segment_key = key
      cidr_block  = cidrsubnet(var.network_baseline.cidr_block, var.network_baseline.cidr_subnet_bits, item.config.cidr_index)

      # Paired NAT subnet
      nat_gateway    = cidrhost(cidrsubnet(var.network_baseline.cidr_block, var.network_baseline.cidr_subnet_bits, item.config.cidr_index - var.network_baseline.cidr_nat_offset), 1)
      nat_cidr_block = cidrsubnet(var.network_baseline.cidr_block, var.network_baseline.cidr_subnet_bits, item.config.cidr_index - var.network_baseline.cidr_nat_offset)
      nat_cidr_index = item.config.cidr_index - var.network_baseline.cidr_nat_offset

      nat_dhcp = {
        start = cidrhost(cidrsubnet(var.network_baseline.cidr_block, var.network_baseline.cidr_subnet_bits, item.config.cidr_index - var.network_baseline.cidr_nat_offset), 100)
        end   = cidrhost(cidrsubnet(var.network_baseline.cidr_block, var.network_baseline.cidr_subnet_bits, item.config.cidr_index - var.network_baseline.cidr_nat_offset), 199)
      }

      # Deterministic bridge name
      interface_alias = "v_${substr(replace(key, "-", ""), 0, 8)}_${substr(item.hash_prefix, 0, 4)}"
      vrid            = item.config.cidr_index
      runtime         = item.config.runtime
      ip_range        = item.config.ip_range
      ports           = coalesce(item.config.ports, {})
      tags            = coalesce(item.config.tags, [])

      # Segment VIP
      vip = cidrhost(
        cidrsubnet(var.network_baseline.cidr_block, var.network_baseline.cidr_subnet_bits, item.config.cidr_index),
        var.network_baseline.host_vip_offset
      )

      # Deterministic MAC address
      mac_address = "${var.network_baseline.global_mac_prefix}:${join(":", [
        substr(md5("${item.config.cidr_index}${key}"), 0, 2),
        substr(md5("${item.config.cidr_index}${key}"), 2, 2),
        substr(md5("${item.config.cidr_index}${key}"), 4, 2)
      ])}"

      # Reserved-range node IPs
      node_ips = [
        for i in range(item.config.ip_range.end_ip - item.config.ip_range.start_ip + 1) :
        cidrhost(cidrsubnet(var.network_baseline.cidr_block, var.network_baseline.cidr_subnet_bits, item.config.cidr_index), item.config.ip_range.start_ip + i)
      ]
    }
  }

  # Global DNS registry, SSoT for Libvirt DNS injection
  dns_records = flatten([
    for key, pki in local.pki_map : [
      for san in pki.dns_san : {
        hostname = san
        ip       = local.network_topology[key].vip
      }
    ]
  ])
}

# service-catalog: Volume Topology

locals {
  # Cartesian product of segment, node, and disk
  _volume_topology_raw = flatten([
    for key, item in local._flat_catalog : [
      for i in range(item.config.ip_range.end_ip - item.config.ip_range.start_ip + 1) : [
        for disk in item.config.data_disks : {
          base_id      = item.cluster_name
          pool_name    = item.storage_pool_name
          volume_name  = "${item.cluster_name}-node-${item.config.ip_range.start_ip + i}-${disk.name_suffix}.qcow2"
          capacity_gib = disk.capacity_gib
        }
      ]
    ]
    if length(coalesce(item.config.data_disks, [])) > 0
  ])

  # Volume topology, keyed by volume name
  volume_topology = {
    for vol in local._volume_topology_raw : vol.volume_name => vol
  }
}
