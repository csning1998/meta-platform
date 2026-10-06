
# Multi-node control plane topology hosts co-located SPIRE server and agent control plane workloads.
# L2 announcement enables upstream Vault discovery of the child SPIRE OIDC provider address.
module "helm_chart_cilium" {
  source = "../../modules/kubernetes-addons/helm-chart-cilium"

  helm_config = {
    chart_repository   = local.chart_repository
    version            = var.helm_chart_version.cilium
    kubernetes_version = var.talos_config.kubernetes_version
  }
  cilium_config = {
    kubeprism_port = var.talos_config.kubeprism_port
    node_count     = length(var.node_config)
    mtu            = local.state.foundation_libvirt_resources.foundation_global.network_baseline.global_mtu
  }
}

module "platform_spire_child" {
  source = "../../modules/kvm-provisioning/orchestrate/linux-talos-cluster"

  svc_identity               = local.svc_identity
  svc_network_map            = { (local.svc_cluster_name) = local.svc_network }
  network_infrastructure_map = { (local.svc_cluster_name) = local.state.foundation_libvirt_resources.foundation_topology.infrastructure[local.svc_cluster_name].network }
  talos_iso_path             = "${local.state.foundation_libvirt_resources.foundation_paths.packer_output}/talos-${trimprefix(var.talos_config.talos_version, "v")}/metal-amd64.iso"
  talos_config               = var.talos_config
  node_config                = var.node_config
  inline_manifests           = module.helm_chart_cilium.inline_manifests
}

# Kubeconfig and TLS client credentials MUST be published to the Downstream KV for downstream automation.
module "credentials_spire_child" {
  source    = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version   = "0.1.1"
  providers = { vault = vault.downstream }

  vault_credential_context = {
    kv_namespace = dirname(dirname(local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["spire"]["child"].cluster_config))
    domain       = basename(dirname(local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["spire"]["child"].cluster_config))
    component    = basename(local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["spire"]["child"].cluster_config)
    static = {
      talos_ca_certificate_b64     = module.platform_spire_child.client_configuration.ca_certificate
      talos_client_certificate_b64 = module.platform_spire_child.client_configuration.client_certificate
      talos_client_key_b64         = module.platform_spire_child.client_configuration.client_key
      content_b64                  = base64encode(module.platform_spire_child.kubeconfig_raw)
    }
  }
}
