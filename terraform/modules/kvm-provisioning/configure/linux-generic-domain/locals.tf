
locals {
  # Deduplicates base image paths to prevent redundant Copy-on-Write backing volume creation.
  unique_base_images = toset([for k, v in var.guest_config.all_nodes_map : abspath(v.base_image_path)])

  base_image_map = {
    for path in local.unique_base_images : basename(path) => path
  }
}

locals {
  nodes_config = {
    for node_name, node_config in var.guest_config.all_nodes_map :
    node_name => {
      node_index = index(keys(var.guest_config.all_nodes_map), node_name)

      nat_mac      = module.deterministic_mac.macs["${node_name}/nat"]
      hostonly_mac = module.deterministic_mac.macs["${node_name}/hostonly"]

      hostonly_ip_cidr = "${node_config.ip}/${var.libvirt_infrastructure[node_config.network_tier].network.hostonly.ips.prefix}"

      # Maps extra networks to deterministic MACs, static CIDRs, and systemd-networkd stable aliases.
      # Precludes reliance on kernel PCI-slot probe order for VRRP and routing bindings.
      extra_network_interfaces = {
        for net, cidr in node_config.extra_networks : net => {
          mac     = module.deterministic_mac.macs["${node_name}/${net}"]
          address = cidr
          alias   = module.interface_alias[net].alias
        }
      }
    }
  }
}

# The NAT seed is the node IP, the HostOnly seed adds a suffix, and each extra network seed adds the network name.
module "deterministic_mac" {
  source = "../../helpers/deterministic-mac"

  seeds = merge([
    for node_name, node_config in var.guest_config.all_nodes_map : merge(
      {
        "${node_name}/nat"      = node_config.ip
        "${node_name}/hostonly" = "${node_config.ip}-hostonly"
      },
      { for net, cidr in node_config.extra_networks : "${node_name}/${net}" => "${node_config.ip}-${net}" }
    )
  ]...)
}
