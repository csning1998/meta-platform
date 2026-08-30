
module "context" {
  source = "../../modules/kvm-provisioning/layer-context"

  global_topology_identity = data.terraform_remote_state.metadata.outputs.global_topology_identity
  global_topology_network  = data.terraform_remote_state.metadata.outputs.global_topology_network
  global_pki_map           = data.terraform_remote_state.metadata.outputs.global_pki_map
  global_network_baseline  = data.terraform_remote_state.metadata.outputs.global_network_baseline
  infrastructure_map       = data.terraform_remote_state.metadata.outputs.infrastructure_map
  guest_vm_data            = data.vault_kv_secret_v2.guest_vm.data

  target_clusters = var.target_clusters
  primary_role    = var.primary_role
  service_config  = var.service_config
}

module "platform_spire_parent" {
  source            = "../../modules/kvm-provisioning/ha-service-kvm-general"
  ansible_root_path = abspath("${path.root}/../../../ansible")
  scripts_root_path = abspath("${path.root}/../../../shell")

  svc_identity               = module.context.svc_identity
  node_identities            = module.context.node_identities
  topology_cluster           = module.context.topology_cluster
  network_infrastructure_map = module.context.network_infrastructure_map
  credentials_system         = module.context.sec_vm_credentials
  static_routes              = module.context.asymmetric_static_routes
  storage_infrastructure_map = data.terraform_remote_state.metadata.outputs.storage_infrastructure_map

  ansible_generic_config = {
    template_vars = local.ansible_template_config
    extra_vars    = local.ansible_extra_config
  }
}
