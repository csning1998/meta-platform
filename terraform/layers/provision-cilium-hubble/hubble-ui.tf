
# GatewayClass declaration enables Cilium gateway-controller reconciliation for downstream Gateway resources.
resource "kubernetes_manifest" "gateway_class" {
  depends_on = [ephemeral.talos_cluster_health.this]

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata   = { name = "cilium" }
    spec       = { controllerName = "io.cilium/gateway-controller" }
  }
}

module "kubernetes_cilium_hubble" {
  source     = "../../modules/kubernetes-addons/cilium-hubble"
  depends_on = [ephemeral.talos_cluster_health.this]

  hubble_ui_config = {
    namespace = "platform-hubble"
    gateway_vip = cidrhost(
      local.state.foundation_libvirt_resources.foundation_topology.network["cilium"]["hubble"].cidr_block,
      local.state.foundation_libvirt_resources.foundation_global.network_baseline.host_vip_offset + 1
    )
    kv_path = one(local.external_secrets.kv_paths)

    # Subdomain matches the SAN policy of the Downstream PKI role of this cluster and requires external static DNS resolution.
    hostname = "hubble.${local.state.foundation_libvirt_resources.foundation_pki.map["cilium-hubble"].dns_san[0]}"
  }

  gateway_config = {
    class_name        = kubernetes_manifest.gateway_class.manifest.metadata.name
    secret_store_name = kubernetes_manifest.downstream_vault_store.manifest.metadata.name
    lb_policy_name    = "${local.project_code}-hubble-ui"
    issuer_ref        = module.platform_cluster_issuer.cluster_issuer
  }
}
