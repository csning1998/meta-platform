
module "context" {
  source = "../../modules/kvm-provisioning/layer-context"

  global_topology_identity = local.state.foundation_libvirt_resources.foundation_topology.identity
  global_topology_network  = local.state.foundation_libvirt_resources.foundation_topology.network
  global_pki_map           = local.state.foundation_libvirt_resources.foundation_pki.map
  global_network_baseline  = local.state.foundation_libvirt_resources.foundation_global.network_baseline
  infrastructure_map       = local.state.foundation_libvirt_resources.foundation_topology.infrastructure
  prod_vault_svc_vip       = local.state.security_vault_downstream_tenants.service_vip
  security_pki_outputs     = local.state.security_vault_downstream_pki
  guest_vm_data            = data.vault_kv_secret_v2.guest_vm.data

  target_clusters = var.target_clusters
  primary_role    = var.primary_role
  service_config  = var.service_config
}

module "platform_harbor_origin" {
  source            = "../../modules/kvm-provisioning/ha-service-kvm-general"
  ansible_root_path = abspath("${path.root}/../../../ansible")
  scripts_root_path = abspath("${path.root}/../../../shell")

  svc_identity                  = module.context.svc_identity
  node_identities               = module.context.node_identities
  topology_cluster              = module.context.topology_cluster
  network_infrastructure_map    = module.context.network_infrastructure_map
  storage_infrastructure_map    = local.state.foundation_libvirt_resources.foundation_storage.infrastructure
  security_pki_bundle_b64       = local.downstream_pki_listener_bundle
  security_vault_agent_identity = local.sec_vault_agent_identity
  ssh_config_path               = local.state.foundation_libvirt_resources.foundation_ssh.config_paths[module.context.svc_identity.cluster_name]

  # Guest authentication MUST combine cluster-specific SSH keypairs from foundation resources
  # with shared baseline credentials from Vault storage.
  credentials_system = merge(module.context.sec_vm_credentials, {
    ssh_private_key_path = local.state.foundation_libvirt_resources.foundation_ssh.identity_key_paths[module.context.svc_identity.cluster_name]
    ssh_public_key_path  = local.state.foundation_libvirt_resources.foundation_ssh.public_key_paths[module.context.svc_identity.cluster_name]
  })

  ansible_generic_config = {
    template_vars = local.ansible_template_vars
    extra_vars    = local.ansible_extra_vars
  }
}
