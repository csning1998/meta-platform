
module "context" {
  source = "../../modules/kvm-provisioning/layer-context"

  global_topology_identity = local.state.network.foundation_topology.identity
  global_topology_network  = local.state.network.foundation_topology.network
  global_pki_map           = local.state.network.foundation_pki.map
  global_network_baseline  = local.state.network.foundation_global.network_baseline
  infrastructure_map       = local.state.network.foundation_topology.infrastructure
  guest_vm_data            = data.vault_generic_secret.guest_vm.data

  target_clusters = var.target_clusters
  primary_role    = var.primary_role
  service_config  = var.service_config
}

# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item D, Section 5.
module "spire_workload_identity" {
  source = "../../modules/vault-provisioning/vault-spiffe-workload-identity-federation"

  auth_role_name    = module.context.svc_identity.cluster_name
  auth_backend_path = local.state.spire_parent.spire_oidc_auth_backend_path
  spiffe_id         = local.spire_workload_spiffe_id
  pki_role_name     = local.harbor_pki_role_name
  pki_mount_path    = local.state.vault_bastion.bastion_vault_pki.intermediate_mount_path
}

module "platform_harbor_origin" {
  source            = "../../modules/kvm-provisioning/ha-service-kvm-general"
  ansible_root_path = abspath("${path.root}/../../../ansible")
  scripts_root_path = abspath("${path.root}/../../../shell")

  svc_identity               = module.context.svc_identity
  node_identities            = module.context.node_identities
  topology_cluster           = module.context.topology_cluster
  network_infrastructure_map = module.context.network_infrastructure_map
  storage_infrastructure_map = local.state.network.foundation_storage.infrastructure
  security_pki_bundle_b64    = local.bastion_pki_listener_bundle
  ssh_config_path            = local.state.network.foundation_ssh.config_paths[module.context.svc_identity.cluster_name]

  # Guest authentication MUST combine cluster-specific SSH keypairs from foundation resources
  # with shared baseline credentials from Vault storage.
  credentials_system = merge(module.context.sec_vm_credentials, {
    ssh_private_key_path = local.state.network.foundation_ssh.identity_key_paths[module.context.svc_identity.cluster_name]
    ssh_public_key_path  = local.state.network.foundation_ssh.public_key_paths[module.context.svc_identity.cluster_name]
  })

  ansible_generic_config = {
    template_vars = local.ansible_template_vars
    extra_vars    = local.ansible_extra_vars
  }
}
