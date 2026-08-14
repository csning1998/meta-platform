
output "hostonly_addresses" {
  description = "Static HostOnly interface IP addresses per node, extracted from interface index 1 following the NAT-first, HostOnly-second convention."
  value = {
    for key, node in var.talos_cluster_vm_config.nodes :
    key => split("/", node.interfaces[1].addresses[0])[0]
  }
}

output "maintenance_addresses" {
  description = "Per-node NAT IPv4 address during Talos maintenance mode, resolved from libvirt DHCP leases matched by NAT interface MAC address."
  value = {
    for key, node in var.talos_cluster_vm_config.nodes :
    key => one([
      for addr in flatten([
        for iface in data.libvirt_domain_interface_addresses.nodes[key].interfaces :
        iface.addrs if lower(iface.hwaddr) == lower(node.interfaces[0].mac)
      ]) : addr.addr if addr.type == "ipv4"
    ])
  }
}
