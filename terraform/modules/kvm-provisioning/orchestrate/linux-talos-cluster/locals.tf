
locals {
  svc_net = var.svc_network_map[var.svc_identity.cluster_name]
  infra   = var.network_infrastructure_map[var.svc_identity.cluster_name]

  # The rule priorities start ahead of the main table rule at 32766, and the table number stays clear of the reserved 253 to 255.
  hostonly_link = {
    alias         = "hostonly"
    route_table   = "100"
    rule_priority = 1000
  }

  # net_node_naming_map re-keys tfvars keys such as "00" to "<node prefix>-NN".
  net_node_naming_map = {
    for idx, key in sort(keys(var.node_config)) : key => "${var.svc_identity.node_name_prefix}-${format("%02d", idx)}"
  }
  nodes = { for key, spec in var.node_config : local.net_node_naming_map[key] => spec }

  sorted_node_keys   = sort(keys(local.nodes))
  bootstrap_node_key = local.sorted_node_keys[0]

  net_service_segments = [
    for seg in var.network_service_segments : merge(seg, {
      node_ips = { for name, spec in local.nodes : name => cidrhost(seg.cidr, spec.ip_suffix) }
    })
  ]

  # The foundation layer names a data volume "<node prefix>-<ip suffix>-<name>". The attached volumes follow the sorted volume keys.
  node_attached_volumes = {
    for name, spec in local.nodes : name => [
      for vol_key in sort(keys(var.storage_infrastructure_map)) : {
        pool           = var.storage_infrastructure_map[vol_key].pool_name
        volume         = var.storage_infrastructure_map[vol_key].volume_name
        os_disk_format = var.storage_infrastructure_map[vol_key].os_disk_format
      }
      if startswith(vol_key, "${var.svc_identity.node_name_prefix}-${spec.ip_suffix}-")
    ]
  }

  # The user volume formats the data disk and mounts the disk at /var/mnt/<name>.
  volume_patches = var.volume_config == null ? [] : [yamlencode({
    apiVersion = "v1alpha1"
    kind       = "UserVolumeConfig"
    name       = var.volume_config.name
    provisioning = {
      diskSelector = { match = "disk.dev_path == '${var.volume_config.device}'" }
      minSize      = "1GiB"
    }
  })]

  # Talos 1.13 declares registry mirrors as separate documents. overridePath keeps the project path of the pull-through cache.
  registry_patches = var.registry_mirror_config == null ? [] : concat(
    [for domain, project in var.registry_mirror_config.mirrors : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "RegistryMirrorConfig"
      name       = domain
      endpoints  = [{ url = "https://${var.registry_mirror_config.host}/v2/${project}", overridePath = true }]
    })],
    [yamlencode({
      apiVersion = "v1alpha1"
      kind       = "RegistryTLSConfig"
      name       = var.registry_mirror_config.host
      ca         = var.registry_mirror_config.ca_pem
    })]
  )

  # The cilium manifest comes first. The other manifests follow in key order.
  ordered_inline_manifests = concat(
    [{ name = "cilium", contents = var.inline_manifests["cilium"] }],
    [for name in sort(keys(var.inline_manifests)) : { name = name, contents = var.inline_manifests[name] } if name != "cilium"]
  )

  talos_cluster_vm_config = {
    storage_pool_name = module.talos_interface_planner.cluster_vm_config.storage_pool_name
    nodes = {
      for name, node in module.talos_interface_planner.cluster_vm_config.nodes : name => {
        vcpu                 = node.vcpu
        ram                  = node.ram
        os_disk_capacity_gib = node.os_disk_capacity_gib
        interfaces           = node.interfaces
        attached_volumes     = local.node_attached_volumes[name]
      }
    }
  }

  hostonly_addresses = module.linux_talos_domain.hostonly_addresses
  # The control plane VIP MUST bind to the canonical service catalog address
  # through Talos leader election to provide a resilient cluster endpoint.
  cluster_endpoint = "https://${local.svc_net.vip}:6443"
}

check "talos_iso_present" {
  assert {
    condition     = fileexists(var.talos_iso_path)
    error_message = "Talos ISO missing at ${var.talos_iso_path}. Build it via packer before applying this layer."
  }
}

check "node_count_matches_catalog" {
  assert {
    condition     = length(var.node_config) == length(local.svc_net.node_ips)
    error_message = "node_config MUST declare one node per address of the ip_range in the service catalog."
  }
}

check "data_disk_attached" {
  assert {
    condition     = var.volume_config == null || alltrue([for name, volumes in local.node_attached_volumes : length(volumes) > 0])
    error_message = "Every node requires one data volume from the foundation storage map, named <node prefix>-<ip suffix>-<name>."
  }
}
