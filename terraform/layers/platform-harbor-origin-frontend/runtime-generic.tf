
module "terraform_layer_context" {
  source = "../../modules/kvm-provisioning/helpers/terraform-layer-context"

  global_topology_identity     = local.state.foundation_libvirt_resources.foundation_topology.identity
  global_topology_network      = local.state.foundation_libvirt_resources.foundation_topology.network
  global_pki_map               = local.state.foundation_libvirt_resources.foundation_pki.map
  global_network_baseline      = local.state.foundation_libvirt_resources.foundation_network_global.network_baseline
  infrastructure_map           = local.state.foundation_libvirt_resources.foundation_topology.infrastructure
  downstream_vault_service_vip = local.state.security_vault_downstream_tenants.downstream_vault_service_vip
  security_pki_outputs         = local.state.security_vault_downstream_pki
  guest_usernames              = local.state.foundation_libvirt_resources.foundation_ssh.usernames

  target_clusters = local.target_clusters
  primary_role    = var.primary_role
  service_config  = var.service_config
}

module "establish_platform_harbor_origin_generic_cluster" {
  source            = "../../modules/kvm-provisioning/orchestrate/linux-generic-cluster"
  ansible_root_path = local.state.foundation_libvirt_resources.foundation_paths.ansible_root
  scripts_root_path = local.state.foundation_libvirt_resources.foundation_paths.scripts_root

  cluster_identity              = module.terraform_layer_context.cluster_identity
  node_identities               = module.terraform_layer_context.node_identities
  topology_cluster              = module.terraform_layer_context.topology_cluster
  network_infrastructure_map    = module.terraform_layer_context.network_infrastructure_map
  storage_infrastructure_map    = local.state.foundation_libvirt_resources.foundation_storage.infrastructure
  security_pki_bundle_b64       = local.downstream_pki_listener_bundle
  security_vault_agent_identity = local.security_vault_agent_identity
  ssh_config_path               = local.state.foundation_libvirt_resources.foundation_ssh.config_paths[module.terraform_layer_context.cluster_identity.cluster_name]

  # Guest authentication MUST combine cluster-specific SSH keypairs from foundation resources
  # with shared baseline credentials from Vault storage.
  credentials_system = merge(module.terraform_layer_context.security_vm_credentials, {
    ssh_private_key_path = local.state.foundation_libvirt_resources.foundation_ssh.identity_key_paths[module.terraform_layer_context.cluster_identity.cluster_name]
    ssh_public_key_path  = local.state.foundation_libvirt_resources.foundation_ssh.public_key_paths[module.terraform_layer_context.cluster_identity.cluster_name]
  })

  ansible_generic_config = {
    template_vars = local.ansible_template_vars
    extra_vars    = local.ansible_extra_vars
  }
}
