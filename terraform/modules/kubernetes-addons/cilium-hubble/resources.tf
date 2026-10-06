
# Hubble UI ingress requires local reverse proxy authentication and Gateway API TLS termination.
locals {
  service_labels = { "io.kubernetes.service.namespace" = var.hubble_ui_config.namespace }

  proxy_name   = "oauth2-proxy"
  gateway_name = "hubble-ui"
  auth_secret  = "hubble-ui-auth"
  tls_secret   = "hubble-ui-tls"
  secret_mount = "/etc/oauth2-proxy"
}

# Cilium IP pool targets dynamically named Gateway LoadBalancer services by namespace selector.
resource "kubernetes_manifest" "ip_pool" {
  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumLoadBalancerIPPool"
    metadata   = { name = var.gateway_config.lb_policy_name }
    spec = {
      serviceSelector = { matchLabels = local.service_labels }
      blocks          = [{ cidr = "${var.hubble_ui_config.gateway_vip}/32" }]
    }
  }
}

resource "kubernetes_manifest" "l2_announcement" {
  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumL2AnnouncementPolicy"
    metadata   = { name = var.gateway_config.lb_policy_name }
    spec = {
      serviceSelector = { matchLabels = local.service_labels }
      loadBalancerIPs = true
    }
  }
}

resource "kubernetes_namespace_v1" "hubble_ui" {
  metadata {
    name = var.hubble_ui_config.namespace
  }
}

resource "kubernetes_manifest" "certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = local.tls_secret
      namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
    }
    spec = {
      secretName = local.tls_secret
      dnsNames   = [var.hubble_ui_config.hostname]
      issuerRef  = var.gateway_config.issuer_ref
      privateKey = {
        algorithm      = "ECDSA"
        size           = 256
        rotationPolicy = "Always"
      }
    }
  }

  # Cert-manager issuance condition MUST reach Ready before Gateway binds the referenced secret.
  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }
}

# ExternalSecret fetches Vault credentials and executes in-cluster bcrypt hash templating.
resource "kubernetes_manifest" "auth" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.auth_secret
      namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { kind = "ClusterSecretStore", name = var.gateway_config.secret_store_name }
      target = {
        name = local.auth_secret
        template = {
          engineVersion = "v2"
          data = {
            htpasswd      = "{{ htpasswd \"${var.hubble_ui_config.login_user}\" .password \"bcrypt\" }}"
            cookie_secret = "{{ .cookie_secret }}"
          }
        }
      }
      data = [
        { secretKey = "password", remoteRef = { key = var.hubble_ui_config.kv_path, property = "password" } },
        { secretKey = "cookie_secret", remoteRef = { key = var.hubble_ui_config.kv_path, property = "cookie_secret" } },
      ]
    }
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }
}

resource "kubernetes_deployment_v1" "oauth2_proxy" {
  depends_on = [kubernetes_manifest.auth]

  metadata {
    name      = local.proxy_name
    namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = local.proxy_name }
    }

    template {
      metadata {
        labels = { app = local.proxy_name }
      }

      spec {
        container {
          name  = local.proxy_name
          image = var.oauth2_proxy_config.image

          image_pull_policy = "Always"

          # Oauth2-proxy requires static provider configuration while delegating authentication to htpasswd credentials.
          args = [
            "--http-address=0.0.0.0:${var.oauth2_proxy_config.port}",
            "--upstream=${var.hubble_ui_config.upstream}",
            "--htpasswd-file=${local.secret_mount}/htpasswd",
            "--email-domain=*",
            "--reverse-proxy=true",
            "--cookie-secure=true",
            "--redirect-url=https://${var.hubble_ui_config.hostname}/oauth2/callback",
            "--provider=google",
            "--client-id=unused",
            "--client-secret=unused",
            "--cookie-secret-file=${local.secret_mount}/cookie_secret",
          ]

          port {
            container_port = var.oauth2_proxy_config.port
          }

          liveness_probe {
            http_get {
              path = "/ping"
              port = var.oauth2_proxy_config.port
            }
            period_seconds = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = var.oauth2_proxy_config.port
            }
            period_seconds = 5
          }

          volume_mount {
            name       = "auth"
            mount_path = local.secret_mount
            read_only  = true
          }

          security_context {
            run_as_non_root            = true
            read_only_root_filesystem  = true
            allow_privilege_escalation = false

            capabilities {
              drop = ["ALL"]
            }
          }

          resources {
            requests = { cpu = "10m", memory = "32Mi" }
            limits   = { cpu = "100m", memory = "128Mi" }
          }
        }

        volume {
          name = "auth"
          secret {
            secret_name = local.auth_secret
            items {
              key  = "htpasswd"
              path = "htpasswd"
            }
            items {
              key  = "cookie_secret"
              path = "cookie_secret"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "oauth2_proxy" {
  metadata {
    name      = local.proxy_name
    namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
  }

  spec {
    selector = { app = local.proxy_name }

    port {
      port        = 80
      target_port = var.oauth2_proxy_config.port
    }
  }
}

resource "kubernetes_manifest" "gateway" {
  depends_on = [
    kubernetes_manifest.certificate,
    kubernetes_manifest.ip_pool,
    kubernetes_manifest.l2_announcement,
  ]

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = local.gateway_name
      namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
    }
    spec = {
      gatewayClassName = var.gateway_config.class_name
      listeners = [{
        name     = "https"
        protocol = "HTTPS"
        port     = 443
        hostname = var.hubble_ui_config.hostname
        tls = {
          mode            = "Terminate"
          certificateRefs = [{ kind = "Secret", name = local.tls_secret }]
        }
        allowedRoutes = { namespaces = { from = "Same" } }
      }]
    }
  }

  # Gateway manifest wait condition MUST verify the Cilium Gateway API controller has programmed the VIP.
  wait {
    condition {
      type   = "Programmed"
      status = "True"
    }
  }
}

resource "kubernetes_manifest" "route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = local.gateway_name
      namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
    }
    spec = {
      parentRefs = [{ name = kubernetes_manifest.gateway.manifest.metadata.name }]
      hostnames  = [var.hubble_ui_config.hostname]
      rules = [{
        backendRefs = [{ name = kubernetes_service_v1.oauth2_proxy.metadata[0].name, port = 80 }]
      }]
    }
  }
}
