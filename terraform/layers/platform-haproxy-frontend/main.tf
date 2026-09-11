
module "context" {
  source = "../../modules/kvm-provisioning/layer-context"

  global_topology_identity = local.state.network.global_topology_identity
  global_topology_network  = local.state.network.global_topology_network
  global_pki_map           = local.state.network.global_pki_map
  global_network_baseline  = local.state.network.global_network_baseline
  infrastructure_map       = local.state.network.infrastructure_map
  guest_vm_data            = data.vault_generic_secret.guest_vm.data

  target_clusters = var.target_clusters
  primary_role    = var.primary_role
  service_config  = local.service_config
}

module "keepalived_credential" {
  source = "../../modules/vault-provisioning/vault-credential"

  vault_kv_namespace = local.vault_kv_namespace
  domain             = "haproxy"
  component          = "frontend"

  generate = {
    keepalived_auth_pass = { length = 32 }
  }
}

module "interface_alias" {
  source   = "../../modules/kvm-provisioning/interface-alias"
  for_each = local.fronted_segments

  name = each.key
}

module "spire_workload_identity" {
  source = "../../modules/vault-provisioning/vault-spiffe-workload-identity-federation"

  auth_role_name    = "${module.context.svc_identity.cluster_name}-workload"
  auth_backend_path = local.state.spire_parent.spire_oidc_auth_backend_path
  spiffe_id         = local.spire_workload_spiffe_id
  pki_role_name     = local.haproxy_pki_role_name
  pki_mount_path    = local.state.vault_bastion.bastion_pki_inter_mount_path
}

module "platform_haproxy_frontend" {
  source            = "../../modules/kvm-provisioning/ha-service-kvm-general"
  ansible_root_path = abspath("${path.root}/../../../ansible")
  scripts_root_path = abspath("${path.root}/../../../shell")

  svc_identity               = module.context.svc_identity
  node_identities            = module.context.node_identities
  topology_cluster           = module.context.topology_cluster
  network_infrastructure_map = module.context.network_infrastructure_map
  storage_infrastructure_map = local.state.network.storage_infrastructure_map
  ssh_config_path            = local.state.network.ssh_config_paths[module.context.svc_identity.cluster_name]

  credentials_system = merge(module.context.sec_vm_credentials, {
    ssh_private_key_path = local.state.network.ssh_identity_key_paths[module.context.svc_identity.cluster_name]
    ssh_public_key_path  = local.state.network.ssh_public_key_paths[module.context.svc_identity.cluster_name]
  })

  ansible_generic_config = {
    template_vars = local.ansible_template_config
    extra_vars    = local.ansible_extra_config
  }
}
