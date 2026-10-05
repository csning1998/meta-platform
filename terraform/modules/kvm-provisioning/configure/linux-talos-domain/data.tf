
# CPU pinning MUST allocate the topmost cores of the Libvirt hypervisor to Talos control
# plane nodes because unpinned domains migrate toward lower-numbered cores, creating contention
# across the lower index range. Each node offset MUST equal the cumulative vCPU count of preceding nodes in sorted order.
locals {
  talos_node_keys_sorted = sort(keys(var.talos_cluster_vm_config.nodes))
  talos_total_vcpus      = sum([for k in local.talos_node_keys_sorted : var.talos_cluster_vm_config.nodes[k].vcpu])
  talos_core_base        = data.libvirt_node_info.host.cpu_cores_total - local.talos_total_vcpus
  talos_node_core_offset = {
    for idx, key in local.talos_node_keys_sorted : key => local.talos_core_base + sum(concat([0], [
      for k in slice(local.talos_node_keys_sorted, 0, idx) : var.talos_cluster_vm_config.nodes[k].vcpu
    ]))
  }
}

data "libvirt_node_info" "host" {}

data "libvirt_domain_interface_addresses" "nodes" {
  for_each = var.talos_cluster_vm_config.nodes

  # Domain interface address queries require domain UUIDs. Numeric domain runtime IDs (`id`) are rejected.
  domain = libvirt_domain.nodes[each.key].uuid
  source = "lease"

  # Postcondition checks MUST validate lease list boundaries to provide diagnostic node identification upon failure.
  lifecycle {
    postcondition {
      condition = length([
        for addr in flatten([
          for iface in self.interfaces :
          iface.addrs if lower(iface.hwaddr) == lower(var.talos_cluster_vm_config.nodes[each.key].interfaces[0].mac)
        ]) : addr.addr if addr.type == "ipv4"
      ]) == 1
      error_message = "Expected exactly one IPv4 DHCP lease on the NAT interface (MAC ${var.talos_cluster_vm_config.nodes[each.key].interfaces[0].mac}) for node '${each.key}'; the maintenance-mode address is not yet stable."
    }
  }
}
