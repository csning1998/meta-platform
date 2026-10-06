
# Declarations which both runtimes share. runtime-vm.tf and runtime-talos.tf hold the declarations of one runtime each.
module "terraform_layer_context" {
  source = "../../modules/kvm-provisioning/helpers/terraform-layer-context"

  global_topology_identity = local.state.foundation_libvirt_resources.foundation_topology.identity
  global_topology_network  = local.state.foundation_libvirt_resources.foundation_topology.network
  global_pki_map           = local.state.foundation_libvirt_resources.foundation_pki.map
  global_network_baseline  = local.state.foundation_libvirt_resources.foundation_global.network_baseline
  infrastructure_map       = local.state.foundation_libvirt_resources.foundation_topology.infrastructure
  guest_usernames          = local.state.foundation_libvirt_resources.foundation_ssh.usernames

  target_clusters = var.target_clusters
  primary_role    = var.primary_role
  service_config  = var.service_config
}
