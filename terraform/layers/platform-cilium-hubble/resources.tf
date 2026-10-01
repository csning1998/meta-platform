
# Hubble UI ingress requires local reverse proxy authentication and Gateway API TLS termination.
resource "kubernetes_namespace_v1" "hubble_ui" {
  metadata {
    name = local.entrypoint.namespace
  }
}

resource "kubernetes_manifest" "certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = local.hubble_ui.tls_secret
      namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
    }
    spec = {
      secretName = local.hubble_ui.tls_secret
      dnsNames   = [local.hubble_ui.hostname]
      issuerRef  = local.entrypoint.cluster_issuer
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
      name      = local.hubble_ui.auth_secret
      namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { kind = "ClusterSecretStore", name = local.entrypoint.secret_store }
      target = {
        name = local.hubble_ui.auth_secret
        template = {
          engineVersion = "v2"
          data = {
            htpasswd      = "{{ htpasswd \"${local.hubble_ui.login_user}\" .password \"bcrypt\" }}"
            cookie_secret = "{{ .cookie_secret }}"
          }
        }
      }
      data = [
        { secretKey = "password", remoteRef = { key = local.hubble_ui.kv_path, property = "password" } },
        { secretKey = "cookie_secret", remoteRef = { key = local.hubble_ui.kv_path, property = "cookie_secret" } },
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
    name      = local.hubble_ui.proxy_name
    namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = local.hubble_ui.proxy_name }
    }

    template {
      metadata {
        labels = { app = local.hubble_ui.proxy_name }
      }

      spec {
        container {
          name  = local.hubble_ui.proxy_name
          image = local.hubble_ui.proxy_image

          image_pull_policy = "Always"

          # Oauth2-proxy requires static provider configuration while delegating authentication to htpasswd credentials.
          args = [
            "--http-address=0.0.0.0:${local.hubble_ui.proxy_port}",
            "--upstream=${local.hubble_ui.upstream}",
            "--htpasswd-file=${local.hubble_ui.secret_mount}/htpasswd",
            "--email-domain=*",
            "--reverse-proxy=true",
            "--cookie-secure=true",
            "--redirect-url=https://${local.hubble_ui.hostname}/oauth2/callback",
            "--provider=google",
            "--client-id=unused",
            "--client-secret=unused",
            "--cookie-secret-file=${local.hubble_ui.secret_mount}/cookie_secret",
          ]

          port {
            container_port = local.hubble_ui.proxy_port
          }

          liveness_probe {
            http_get {
              path = "/ping"
              port = local.hubble_ui.proxy_port
            }
            period_seconds = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = local.hubble_ui.proxy_port
            }
            period_seconds = 5
          }

          volume_mount {
            name       = "auth"
            mount_path = local.hubble_ui.secret_mount
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
            secret_name = local.hubble_ui.auth_secret
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
    name      = local.hubble_ui.proxy_name
    namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
  }

  spec {
    selector = { app = local.hubble_ui.proxy_name }

    port {
      port        = 80
      target_port = local.hubble_ui.proxy_port
    }
  }
}

resource "kubernetes_manifest" "gateway" {
  depends_on = [kubernetes_manifest.certificate]

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = local.hubble_ui.gateway_name
      namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
    }
    spec = {
      gatewayClassName = local.hubble_ui.gateway_class
      listeners = [{
        name     = "https"
        protocol = "HTTPS"
        port     = 443
        hostname = local.hubble_ui.hostname
        tls = {
          mode            = "Terminate"
          certificateRefs = [{ kind = "Secret", name = local.hubble_ui.tls_secret }]
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
      name      = local.hubble_ui.gateway_name
      namespace = kubernetes_namespace_v1.hubble_ui.metadata[0].name
    }
    spec = {
      parentRefs = [{ name = kubernetes_manifest.gateway.manifest.metadata.name }]
      hostnames  = [local.hubble_ui.hostname]
      rules = [{
        backendRefs = [{ name = kubernetes_service_v1.oauth2_proxy.metadata[0].name, port = 80 }]
      }]
    }
  }
}
