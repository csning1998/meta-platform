
locals {
  # Extract a map of unique base images to avoid creating duplicate base volumes (Copy-on-Write)
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

      # Pairs each extra network's deterministically-salted MAC address with the caller-assigned static CIDR, keyed by network name.
      # The network segment provides no DHCP service; this local carries every value libvirt_domain and cloud-init require to attach the interface.
      # `alias` is a systemd-networkd set-name derived only from the network name, stable across
      # reboots and MAC changes. Callers binding to this interface by name (Keepalived VRRP,
      # policy routing) do not depend on kernel PCI-slot-ordered device names.
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
