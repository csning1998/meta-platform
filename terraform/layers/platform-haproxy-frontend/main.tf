
module "context" {
  source = "../../modules/kvm-provisioning/layer-context"

  global_topology_identity = local.state.foundation_libvirt_resources.foundation_topology.identity
  global_topology_network  = local.state.foundation_libvirt_resources.foundation_topology.network
  global_pki_map           = local.state.foundation_libvirt_resources.foundation_pki.map
  global_network_baseline  = local.state.foundation_libvirt_resources.foundation_global.network_baseline
  infrastructure_map       = local.state.foundation_libvirt_resources.foundation_topology.infrastructure
  guest_usernames          = local.state.foundation_libvirt_resources.foundation_ssh.usernames

  target_clusters = var.target_clusters
  primary_role    = var.primary_role
  service_config  = local.service_config
}

module "interface_alias" {
  source   = "../../modules/kvm-provisioning/interface-alias"
  for_each = local.fronted_segments

  name = each.key
}

module "spire_workload_identity" {
  source = "../../modules/vault-provisioning/vault-spiffe-workload-identity-federation"

  auth_role_name    = module.context.svc_identity.cluster_name
  auth_backend_path = local.state.platform_spire_parent.spire_oidc_auth_backend_path
  spiffe_id         = local.spire_workload_spiffe_id
  pki_role_name     = local.haproxy_pki_role_name
  pki_mount_path    = local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_mount_path
}

module "platform_haproxy_frontend" {
  source            = "../../modules/kvm-provisioning/ha-service-kvm-general"
  ansible_root_path = abspath("${path.root}/../../../ansible")
  scripts_root_path = abspath("${path.root}/../../../shell")

  svc_identity               = module.context.svc_identity
  node_identities            = module.context.node_identities
  topology_cluster           = module.context.topology_cluster
  network_infrastructure_map = module.context.network_infrastructure_map
  storage_infrastructure_map = local.state.foundation_libvirt_resources.foundation_storage.infrastructure
  ssh_config_path            = local.state.foundation_libvirt_resources.foundation_ssh.config_paths[module.context.svc_identity.cluster_name]

  credentials_system = merge(module.context.sec_vm_credentials, {
    ssh_private_key_path = local.state.foundation_libvirt_resources.foundation_ssh.identity_key_paths[module.context.svc_identity.cluster_name]
    ssh_public_key_path  = local.state.foundation_libvirt_resources.foundation_ssh.public_key_paths[module.context.svc_identity.cluster_name]
  })

  ansible_generic_config = {
    template_vars = local.ansible_template_config
    extra_vars    = local.ansible_extra_config
  }
}
