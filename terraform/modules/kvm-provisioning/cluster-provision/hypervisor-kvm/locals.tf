
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

      # Combine MAC: KVM default OUI (52:54:00) + MD5 Hex String's first 6 bytes
      # format function is used to insert colons
      nat_mac = format("52:54:00:%s:%s:%s",
        substr(md5(node_config.ip), 0, 2),
        substr(md5(node_config.ip), 2, 2),
        substr(md5(node_config.ip), 4, 2)
      )

      # HostOnly interface can use different offsets (e.g. take MD5's 6~12 bytes) to avoid collision with NAT interface
      hostonly_mac = format("52:54:00:%s:%s:%s",
        substr(md5(node_config.ip), 6, 2),
        substr(md5(node_config.ip), 8, 2),
        substr(md5(node_config.ip), 10, 2)
      )

      hostonly_ip_cidr = "${node_config.ip}/${var.libvirt_infrastructure[node_config.network_tier].network.hostonly.ips.prefix}"
    }
  }
}
