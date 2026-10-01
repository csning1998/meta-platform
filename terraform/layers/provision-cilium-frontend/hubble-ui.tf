
# IP pool allocation and L2 announcement policies MUST stay scoped to the cluster provisioning layer.
locals {
  _namespace = "platform-hubble"

  hubble_ui = {
    namespace      = local._namespace
    service_labels = { "io.kubernetes.service.namespace" = local._namespace }
    gateway_vip = cidrhost(
      local.state.platform_cilium_frontend.foundation_topology.network["cilium"]["frontend"].cidr_block,
      local.state.platform_cilium_frontend.foundation_global.network_baseline.host_vip_offset + 1
    )
  }
}


# Cilium IP pool targets dynamically named Gateway LoadBalancer services by namespace selector.
resource "kubernetes_manifest" "hubble_ui_ip_pool" {
  depends_on = [ephemeral.talos_cluster_health.this]

  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumLoadBalancerIPPool"
    metadata   = { name = "${local.project_code}-hubble-ui" }
    spec = {
      serviceSelector = { matchLabels = local.hubble_ui.service_labels }
      blocks          = [{ cidr = "${local.hubble_ui.gateway_vip}/32" }]
    }
  }
}

resource "kubernetes_manifest" "hubble_ui_l2_announcement" {
  depends_on = [ephemeral.talos_cluster_health.this]

  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumL2AnnouncementPolicy"
    metadata   = { name = "${local.project_code}-hubble-ui" }
    spec = {
      serviceSelector = { matchLabels = local.hubble_ui.service_labels }
      loadBalancerIPs = true
    }
  }
}

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

output "hubble_ui_entrypoint" {
  description = "Cluster ingress prerequisites for Hubble UI Gateway, including namespace, VIP, issuer, and secret store."
  value = {
    namespace      = local.hubble_ui.namespace
    gateway_vip    = local.hubble_ui.gateway_vip
    cluster_issuer = module.platform_cluster_issuer.cluster_issuer
    secret_store   = kubernetes_manifest.bastion_vault_store.manifest.metadata.name
  }
}
