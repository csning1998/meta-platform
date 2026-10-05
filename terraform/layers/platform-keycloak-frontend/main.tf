
module "terraform_layer_context" {
  source = "../../modules/kvm-provisioning/helpers/terraform-layer-context"

  guest_usernames          = local.state.foundation_libvirt_resources.foundation_ssh.usernames
  global_pki_map           = local.state.security_vault_downstream_tenants.foundation_pki.map
  global_topology_identity = local.state.foundation_libvirt_resources.foundation_topology.identity
  global_topology_network  = local.state.foundation_libvirt_resources.foundation_topology.network
  global_network_baseline  = local.state.foundation_libvirt_resources.foundation_global.network_baseline
  infrastructure_map       = local.state.foundation_libvirt_resources.foundation_topology.infrastructure
  prod_vault_svc_vip       = local.state.security_vault_downstream_tenants.service_vip
  security_pki_outputs     = local.state.security_vault_downstream_pki

  target_clusters = var.target_clusters
  primary_role    = var.primary_role
  service_config  = var.service_config
}

module "infra_keycloak_cluster" {
  source = "../../modules/kvm-provisioning/orchestrate/linux-generic-cluster"

  count             = local.is_runtime_talos ? 0 : 1
  ansible_root_path = local.state.foundation_libvirt_resources.foundation_paths.ansible_root
  scripts_root_path = local.state.foundation_libvirt_resources.foundation_paths.scripts_root

  svc_identity                  = module.terraform_layer_context.svc_identity
  node_identities               = module.terraform_layer_context.node_identities
  topology_cluster              = module.terraform_layer_context.topology_cluster
  network_infrastructure_map    = module.terraform_layer_context.network_infrastructure_map
  storage_infrastructure_map    = local.state.foundation_libvirt_resources.foundation_storage.infrastructure
  security_vault_agent_identity = local.sec_vault_agent_identity
  ssh_config_path               = local.state.foundation_libvirt_resources.foundation_ssh.config_paths[module.terraform_layer_context.svc_identity.cluster_name]

  # Guest authentication MUST combine cluster-specific SSH keypairs from foundation resources
  # with shared baseline credentials from Vault storage.
  credentials_system = merge(module.terraform_layer_context.sec_vm_credentials, {
    ssh_private_key_path = local.state.foundation_libvirt_resources.foundation_ssh.identity_key_paths[module.terraform_layer_context.svc_identity.cluster_name]
    ssh_public_key_path  = local.state.foundation_libvirt_resources.foundation_ssh.public_key_paths[module.terraform_layer_context.svc_identity.cluster_name]
  })
  ansible_generic_config = {
    template_vars = local.ansible_template_vars
    extra_vars    = local.ansible_extra_vars
  }
}

# The Downstream PKI layer owns the leaf role of this component.
module "vault_auth_keycloak_talos" {
  count     = local.is_runtime_talos ? 1 : 0
  source    = "../../modules/vault-provisioning/vault-kubernetes-auth"
  providers = { vault = vault.downstream }

  cluster_name = local.svc_cluster_name
  pki_config = {
    mount_path         = local.state.security_vault_downstream_pki.prod_pki_configuration.path
    role_name          = local.state.security_vault_downstream_pki.prod_pki_configuration.leaf_roles["keycloak-frontend"].name
    issuer_policy_name = local.downstream_operator.cluster_issuer_policy
  }
  external_secrets_config = {
    kv_paths    = [local.kv_paths["keycloak"]["frontend"].app]
    policy_name = local.downstream_operator.external_secrets_policy
  }
}

module "helm_chart_cilium" {
  count  = local.is_runtime_talos ? 1 : 0
  source = "../../modules/kubernetes-addons/helm-chart-cilium"

  helm_config = {
    chart_repository   = local.registry_mirror.chart_repository
    version            = var.helm_chart_version.cilium
    kubernetes_version = var.talos_config.kubernetes_version
  }
  cilium_config = {
    kubeprism_port = var.talos_config.kubeprism_port
    node_count     = length(var.node_config)
    mtu            = local.state.foundation_libvirt_resources.foundation_global.network_baseline.global_mtu
    gateway_api    = var.talos_config.gateway_api
  }
}

module "helm_chart_cert_manager" {
  count  = local.is_runtime_talos ? 1 : 0
  source = "../../modules/kubernetes-addons/helm-chart-cert-manager"

  helm_config = {
    chart_repository   = local.registry_mirror.chart_repository
    version            = var.helm_chart_version.cert_manager
    kubernetes_version = var.talos_config.kubernetes_version
    namespace          = module.vault_auth_keycloak_talos[0].kubernetes_identity.cert_manager_namespace
  }
}

module "helm_chart_external_secrets" {
  count  = local.is_runtime_talos ? 1 : 0
  source = "../../modules/kubernetes-addons/helm-chart-external-secrets"

  helm_config = {
    chart_repository   = local.registry_mirror.chart_repository
    version            = var.helm_chart_version.external_secrets
    kubernetes_version = var.talos_config.kubernetes_version
    namespace          = module.vault_auth_keycloak_talos[0].kubernetes_identity.external_secrets_namespace
  }
}

module "infra_keycloak_talos" {
  count  = local.is_runtime_talos ? 1 : 0
  source = "../../modules/kvm-provisioning/orchestrate/linux-talos-cluster"

  svc_identity               = module.terraform_layer_context.svc_identity
  svc_network_map            = { (local.svc_cluster_name) = module.terraform_layer_context.svc_network }
  network_infrastructure_map = { (local.svc_cluster_name) = local.state.foundation_libvirt_resources.foundation_topology.infrastructure[local.svc_cluster_name].network }
  storage_infrastructure_map = local.state.foundation_libvirt_resources.foundation_storage.infrastructure
  talos_iso_path             = "${local.state.foundation_libvirt_resources.foundation_paths.packer_output}/talos-${trimprefix(var.talos_config.talos_version, "v")}/metal-amd64.iso"
  talos_config               = var.talos_config
  node_config                = var.node_config
  volume_config              = var.volume_config

  registry_mirror_config = {
    host    = local.registry_mirror.host
    ca_pem  = base64decode(local.state.security_vault_downstream_pki.bastion_pki_chain_b64.content_b64)
    mirrors = local.registry_mirror.mirrors
  }

  inline_manifests = merge(
    module.helm_chart_cilium[0].inline_manifests,
    module.helm_chart_cert_manager[0].inline_manifests,
    module.helm_chart_external_secrets[0].inline_manifests,
  )
}

# The kubeconfig and the Talos client credentials follow the cluster lifecycle in the Downstream Vault.
module "credentials_keycloak_talos" {
  count     = local.is_runtime_talos ? 1 : 0
  source    = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version   = "0.1.1"
  providers = { vault = vault.downstream }

  vault_credential_context = {
    kv_namespace = dirname(dirname(local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["keycloak"]["frontend"].cluster_config))
    domain       = basename(dirname(local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["keycloak"]["frontend"].cluster_config))
    component    = basename(local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["keycloak"]["frontend"].cluster_config)
    static = {
      talos_ca_certificate_b64     = module.infra_keycloak_talos[0].client_configuration.ca_certificate
      talos_client_certificate_b64 = module.infra_keycloak_talos[0].client_configuration.client_certificate
      talos_client_key_b64         = module.infra_keycloak_talos[0].client_configuration.client_key
      content_b64                  = base64encode(module.infra_keycloak_talos[0].kubeconfig_raw)
    }
  }
}
