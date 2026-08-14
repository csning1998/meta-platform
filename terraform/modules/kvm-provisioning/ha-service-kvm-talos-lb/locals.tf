
locals {
  svc_net = var.svc_network_map[var.svc_identity.service_name]
  infra   = var.network_infrastructure_map[var.svc_identity.service_name]

  sorted_node_keys   = sort(keys(var.topology_cluster.load_balancer_config.nodes))
  bootstrap_node_key = local.sorted_node_keys[0]

  # interface_planner requires base_image_path. var.talos_iso_path populates
  # base_image_path to keep MAC and interface calculation shared with cloud-init.
  interface_planner_node_config = {
    for key, node in var.topology_cluster.load_balancer_config.nodes : key => merge(node, {
      base_image_path = var.talos_iso_path
    })
  }

  talos_cluster_vm_config = {
    storage_pool_name = module.interface_planner.lb_cluster_vm_config.storage_pool_name
    nodes = {
      for key, node in module.interface_planner.lb_cluster_vm_config.nodes : key => {
        vcpu                 = node.vcpu
        ram                  = node.ram
        os_disk_capacity_gib = node.os_disk_capacity_gib
        interfaces           = node.interfaces
      }
    }
  }

  hostonly_addresses = module.hypervisor_kvm_talos.hostonly_addresses
  cluster_endpoint   = "https://${local.hostonly_addresses[local.bootstrap_node_key]}:6443"
  # Single point of failure: no SSoT VIP reservation exists for this segment, the same
  # open defect tracked for central-lb in the ADR.
}
