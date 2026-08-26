
module "context" {
  source = "../../modules/kvm-provisioning/layer-context"

  global_topology_identity = local.state.network.global_topology_identity
  global_topology_network  = local.state.network.global_topology_network
  global_pki_map           = local.state.network.global_pki_map
  global_network_baseline  = local.state.network.global_network_baseline
  infrastructure_map       = local.state.network.infrastructure_map
  guest_vm_data            = data.vault_kv_secret_v2.guest_vm.data

  target_clusters = var.target_clusters
  primary_role    = var.primary_role
  service_config  = var.service_config
}

module "infra_harbor_origin" {
  source            = "../../modules/kvm-provisioning/ha-service-kvm-general"
  ansible_root_path = abspath("${path.root}/../../../ansible")
  scripts_root_path = abspath("${path.root}/../../../shell")

  svc_identity               = module.context.svc_identity
  node_identities            = module.context.node_identities
  topology_cluster           = module.context.topology_cluster
  network_infrastructure_map = module.context.network_infrastructure_map
  credentials_system         = module.context.sec_vm_credentials
  storage_infrastructure_map = local.state.network.storage_infrastructure_map
  security_pki_bundle_b64    = local.bastion_pki_listener_bundle
  ansible_generic_config = {
    template_vars = local.ansible_template_vars
    extra_vars    = local.ansible_extra_vars
  }
}
