
resource "kubernetes_namespace_v1" "platform_lb" {
  metadata {
    name = "platform-lb"
  }
}

# Define cluster-scoped IP pool and L2 announcement resources per ADR 20260813_1630.
# Consuming projects maintain ownership of namespaced Service and Endpoints objects.
resource "kubectl_manifest" "lb_ip_pool" {
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumLoadBalancerIPPool"
    metadata = {
      name = "meta-platform-catalog"
    }
    spec = {
      serviceSelector = {
        matchLabels = local.lb_managed_label
      }
      blocks = [
        for key, seg in local.fronted_segments : { cidr = "${seg.lb_config.vip}/32" }
      ]
    }
  })
}

resource "kubectl_manifest" "l2_announcement_policy" {
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumL2AnnouncementPolicy"
    metadata = {
      name = "meta-platform-catalog"
    }
    spec = {
      serviceSelector = {
        matchLabels = local.lb_managed_label
      }
      loadBalancerIPs = true
    }
  })
}

# Bind selector-less LoadBalancer Services to explicit Endpoints objects matching
# by name and namespace for backing address resolution.
resource "kubernetes_service_v1" "catalog" {
  for_each = local.fronted_segments

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.platform_lb.metadata[0].name
    labels    = local.lb_managed_label
    annotations = {
      "io.cilium/lb-ipam-ips" = each.value.lb_config.vip
    }
  }

  spec {
    type = "LoadBalancer"

    dynamic "port" {
      for_each = each.value.lb_config.ports
      content {
        name        = port.key
        port        = port.value.frontend_port
        target_port = port.value.backend_port
        protocol    = "TCP"
      }
    }
  }

  # Prevents uninformative API server validation failures during resource apply operations.
  lifecycle {
    precondition {
      condition = alltrue([
        for port_name in keys(each.value.lb_config.ports) :
        can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", port_name)) && length(port_name) <= 15
      ])
      error_message = "Catalog port keys for '${each.key}' must be valid IANA_SVC_NAMEs (lowercase, <= 15 characters, containing a letter)."
    }
  }
}

resource "kubernetes_endpoints_v1" "catalog" {
  for_each = local.fronted_segments

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.platform_lb.metadata[0].name
  }

  subset {
    dynamic "address" {
      for_each = each.value.backend_servers
      content {
        ip       = address.value.ip
        hostname = address.value.name
      }
    }

    dynamic "port" {
      for_each = each.value.lb_config.ports
      content {
        name     = port.key
        port     = port.value.backend_port
        protocol = "TCP"
      }
    }
  }
}
