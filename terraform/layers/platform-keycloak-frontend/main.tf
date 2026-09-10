
module "context" {
  source = "../../modules/kvm-provisioning/layer-context"

  guest_vm_data            = data.vault_kv_secret_v2.guest_vm.data
  global_pki_map           = data.terraform_remote_state.security_vault_approle.outputs.global_pki_map
  global_topology_identity = data.terraform_remote_state.cilium.outputs.global_topology_identity
  global_topology_network  = data.terraform_remote_state.cilium.outputs.global_topology_network
  global_network_baseline  = data.terraform_remote_state.cilium.outputs.global_network_baseline
  infrastructure_map       = data.terraform_remote_state.cilium.outputs.infrastructure_map
  prod_vault_svc_vip       = data.terraform_remote_state.security_vault_approle.outputs.prod_vault_svc_vip
  security_pki_outputs     = data.terraform_remote_state.security_pki.outputs

  target_clusters = var.target_clusters
  primary_role    = var.primary_role
  service_config  = var.service_config
}

module "infra_keycloak_cluster" {
  source            = "../../modules/kvm-provisioning/ha-service-kvm-general"
  ansible_root_path = abspath("${path.root}/../../../ansible")
  scripts_root_path = abspath("${path.root}/../../../shell")

  svc_identity                  = module.context.svc_identity
  node_identities               = module.context.node_identities
  topology_cluster              = module.context.topology_cluster
  network_infrastructure_map    = module.context.network_infrastructure_map
  storage_infrastructure_map    = data.terraform_remote_state.volume.outputs.storage_infrastructure_map
  security_vault_agent_identity = local.sec_vault_agent_identity
  ssh_config_path               = data.terraform_remote_state.volume.outputs.ssh_config_paths[module.context.svc_identity.cluster_name]

  # Guest authentication MUST combine cluster-specific SSH keypairs from foundation resources
  # with shared baseline credentials from Vault storage.
  credentials_system = merge(module.context.sec_vm_credentials, {
    ssh_private_key_path = data.terraform_remote_state.volume.outputs.ssh_identity_key_paths[module.context.svc_identity.cluster_name]
    ssh_public_key_path  = data.terraform_remote_state.volume.outputs.ssh_public_key_paths[module.context.svc_identity.cluster_name]
  })
  ansible_generic_config = {
    template_vars = local.ansible_template_vars
    extra_vars    = local.ansible_extra_vars
  }
}
