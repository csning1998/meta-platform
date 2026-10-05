
module "talos_interface_planner" {
  source = "../../helpers/talos-interface-planner"

  node_config           = local.nodes
  storage_pool_name     = var.svc_identity.storage_pool_name
  svc_network           = local.svc_net
  network_infra         = local.infra
  svc_network_map       = var.svc_network_map
  service_segment_names = [for seg in local.net_service_segments : seg.name]
}

module "linux_talos_domain" {
  source = "../../configure/linux-talos-domain"

  talos_iso_path                 = var.talos_iso_path
  os_disk_format                 = var.talos_config.os_disk_format
  talos_cluster_vm_config        = local.talos_cluster_vm_config
  network_infrastructure         = var.network_infrastructure_map
  talos_cluster_service_segments = local.net_service_segments
  create_networks                = false
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_config.talos_version
}

# Target pre-configuration node maintenance IP addresses resolved from libvirt DHCP leases.
resource "talos_machine_configuration_apply" "this" {
  depends_on = [module.linux_talos_domain]
  for_each   = local.talos_cluster_vm_config.nodes

  # Configuration patch applications MUST trigger a full node reboot
  # because in-place reconfiguration fails to recover inconsistent in-memory etcd learner states.
  apply_mode = "reboot"

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  node                        = module.linux_talos_domain.maintenance_addresses[each.key]
  endpoint                    = module.linux_talos_domain.maintenance_addresses[each.key]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  node                 = local.hostonly_addresses[local.bootstrap_node_key]
  client_configuration = talos_machine_secrets.this.client_configuration

  timeouts = {
    create = var.talos_config.bootstrap_timeout
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [data.talos_cluster_health.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.hostonly_addresses[local.bootstrap_node_key]
}
