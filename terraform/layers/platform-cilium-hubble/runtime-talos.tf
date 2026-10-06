
# The module owns the PKI role of this cluster, since the role admits the Hubble TLS names which the chart module derives.
module "vault_auth_cilium_hubble" {
  source    = "../../modules/vault-provisioning/vault-kubernetes-auth"
  providers = { vault = vault.downstream }

  cluster_name = local.cilium_hubble_cluster_name
  pki_config = {
    mount_path           = local.state.security_vault_downstream_pki.downstream_pki_configuration.path
    role_allowed_domains = concat(local.cilium_hubble_cluster_pki.dns_san, module.helm_chart_cilium.hubble_tls_domains)
    role_ou              = local.cilium_hubble_cluster_pki.ou
    issuer_policy_name   = local.terraform_operator.cluster_issuer_policy
  }
  external_secrets_config = {
    kv_paths    = ["${local.downstream_kv_paths.addon}-hubble-ui"]
    policy_name = local.terraform_operator.external_secrets_policy
  }
}

module "helm_chart_cilium" {
  source = "../../modules/kubernetes-addons/helm-chart-cilium"

  helm_config = {
    chart_repository   = local.harbor_registry_mirror.chart_repository
    version            = var.helm_chart_version.cilium
    kubernetes_version = var.talos_config.kubernetes_version
  }
  cilium_config = {
    kubeprism_port = var.talos_config.kubeprism_port
    node_count     = length(var.node_config)
    mtu            = local.state.foundation_libvirt_resources.foundation_network_global.network_baseline.global_mtu
    gateway_api    = var.talos_config.gateway_api
  }
  hubble_config = {
    enabled = true
  }
}

module "helm_chart_cert_manager" {
  source = "../../modules/kubernetes-addons/helm-chart-cert-manager"

  helm_config = {
    chart_repository   = local.harbor_registry_mirror.chart_repository
    version            = var.helm_chart_version.cert_manager
    kubernetes_version = var.talos_config.kubernetes_version
    namespace          = module.vault_auth_cilium_hubble.kubernetes_identity.cert_manager_namespace
  }
}

module "helm_chart_external_secrets" {
  source = "../../modules/kubernetes-addons/helm-chart-external-secrets"

  helm_config = {
    chart_repository   = local.harbor_registry_mirror.chart_repository
    version            = var.helm_chart_version.external_secrets
    kubernetes_version = var.talos_config.kubernetes_version
    namespace          = module.vault_auth_cilium_hubble.kubernetes_identity.external_secrets_namespace
  }
}

module "establish_platform_cilium_hubble_talos_cluster" {
  source = "../../modules/kvm-provisioning/orchestrate/linux-talos-cluster"

  cluster_identity           = local.cilium_hubble_cluster_identity
  cluster_network_map        = local.network_map
  network_infrastructure_map = { (local.cilium_hubble_cluster_name) = local.state.foundation_libvirt_resources.foundation_topology.infrastructure[local.cilium_hubble_cluster_name].network }
  network_service_segments   = local.network_service_segments
  talos_iso_path             = "${local.state.foundation_libvirt_resources.foundation_paths.packer_output}/talos-${trimprefix(var.talos_config.talos_version, "v")}/metal-amd64.iso"
  talos_config               = var.talos_config

  registry_mirror_config = {
    host    = local.harbor_registry_mirror.host
    ca_pem  = base64decode(local.state.security_vault_downstream_pki.bastion_pki_chain_b64.content_b64)
    mirrors = local.harbor_registry_mirror.mirrors
  }

  node_config = {
    for key, spec in var.node_config : key => merge(spec, {
      extra_networks = local.bastion_network_nodes[key]
    })
  }

  inline_manifests = merge(
    module.helm_chart_cilium.inline_manifests,
    module.helm_chart_cert_manager.inline_manifests,
    module.helm_chart_external_secrets.inline_manifests,
  )
}

# The kubeconfig follows the cluster lifecycle. This layer writes the kubeconfig to the Downstream Vault.
module "credential_cilium_hubble" {
  source    = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version   = "0.1.1"
  providers = { vault = vault.downstream }

  vault_credential_context = {
    kv_namespace = dirname(dirname(local.foundation_kv_paths.cluster_config))
    domain       = basename(dirname(local.foundation_kv_paths.cluster_config))
    component    = basename(local.foundation_kv_paths.cluster_config)
    static = {
      talos_ca_certificate_b64     = module.establish_platform_cilium_hubble_talos_cluster.client_configuration.ca_certificate
      talos_client_certificate_b64 = module.establish_platform_cilium_hubble_talos_cluster.client_configuration.client_certificate
      talos_client_key_b64         = module.establish_platform_cilium_hubble_talos_cluster.client_configuration.client_key
      content_b64                  = base64encode(module.establish_platform_cilium_hubble_talos_cluster.kubeconfig_raw)
    }
  }
}
