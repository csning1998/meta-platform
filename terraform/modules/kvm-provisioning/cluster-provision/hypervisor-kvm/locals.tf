
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

      # Constructs the NAT MAC address by appending the first 6 hexadecimal characters of md5(node_config.ip) to the KVM default OUI prefix (52:54:00).
      nat_mac = format("52:54:00:%s:%s:%s",
        substr(md5(node_config.ip), 0, 2),
        substr(md5(node_config.ip), 2, 2),
        substr(md5(node_config.ip), 4, 2)
      )

      # Constructs the HostOnly MAC address using MD5 digest bytes 6 through 11 to guarantee address isolation from the NAT interface.
      hostonly_mac = format("52:54:00:%s:%s:%s",
        substr(md5(node_config.ip), 6, 2),
        substr(md5(node_config.ip), 8, 2),
        substr(md5(node_config.ip), 10, 2)
      )

      hostonly_ip_cidr = "${node_config.ip}/${var.libvirt_infrastructure[node_config.network_tier].network.hostonly.ips.prefix}"

      # Pairs each extra network's deterministically-salted MAC address with the caller-assigned static CIDR, keyed by network name.
      # The network segment provides no DHCP service; this local carries every value libvirt_domain and cloud-init require to attach the interface.
      extra_network_interfaces = {
        for net, cidr in node_config.extra_networks : net => {
          mac = format("52:54:00:%s:%s:%s",
            substr(md5("${node_config.ip}-${net}"), 0, 2),
            substr(md5("${node_config.ip}-${net}"), 2, 2),
            substr(md5("${node_config.ip}-${net}"), 4, 2)
          )
          address = cidr
        }
      }
    }
  }
}
