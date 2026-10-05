
# Plain Kubernetes manifests of Keycloak and of the PostgreSQL which holds its database, with neither a Helm chart
# nor the Keycloak Operator. Upstream publishes no chart of the server, and the chart of the Operator is experimental.
locals {
  database_name   = "keycloak"
  database_labels = { "app.kubernetes.io/name" = "keycloak-db" }
  keycloak_labels = { "app.kubernetes.io/name" = "keycloak" }
  tls_mount       = "/opt/keycloak/certs"

  credential_env = {
    admin_user     = { name = var.credential_secret.name, key = var.credential_secret.admin_user_key }
    admin_password = { name = var.credential_secret.name, key = var.credential_secret.admin_password_key }
    db_user        = { name = var.credential_secret.name, key = var.credential_secret.db_user_key }
    db_password    = { name = var.credential_secret.name, key = var.credential_secret.db_password_key }
  }
}

resource "kubernetes_service_v1" "database" {
  metadata {
    name      = "keycloak-db"
    namespace = var.keycloak_config.namespace
  }

  spec {
    type     = "ClusterIP"
    selector = local.database_labels

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_stateful_set_v1" "database" {
  metadata {
    name      = "keycloak-db"
    namespace = var.keycloak_config.namespace
  }

  spec {
    service_name = kubernetes_service_v1.database.metadata[0].name
    replicas     = 1

    selector {
      match_labels = local.database_labels
    }

    template {
      metadata {
        labels = local.database_labels
      }

      spec {
        container {
          name  = "postgres"
          image = var.database_config.image

          env {
            name  = "POSTGRES_DB"
            value = local.database_name
          }
          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = local.credential_env.db_user.name
                key  = local.credential_env.db_user.key
              }
            }
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = local.credential_env.db_password.name
                key  = local.credential_env.db_password.key
              }
            }
          }

          port {
            container_port = 5432
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U \"$POSTGRES_USER\" -d ${local.database_name}"]
            }
            period_seconds = 10
          }

          # The image of PostgreSQL 18 keeps PGDATA in a versioned directory below this mount point.
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql"
          }

          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.database_config.storage_class_name
        resources {
          requests = { storage = var.database_config.storage_size }
        }
      }
    }
  }
}

# A single replica keeps the local cache. Several replicas would need a cache discovery stack, which this module omits.
resource "kubernetes_deployment_v1" "keycloak" {
  depends_on = [kubernetes_stateful_set_v1.database]

  metadata {
    name      = "keycloak"
    namespace = var.keycloak_config.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.keycloak_labels
    }

    template {
      metadata {
        labels = local.keycloak_labels
      }

      spec {
        container {
          name  = "keycloak"
          image = var.keycloak_config.image
          args  = ["start"]

          dynamic "env" {
            for_each = {
              KC_DB                         = "postgres"
              KC_DB_URL                     = "jdbc:postgresql://${kubernetes_service_v1.database.metadata[0].name}.${var.keycloak_config.namespace}.svc:5432/${local.database_name}"
              KC_HOSTNAME                   = var.keycloak_config.hostname
              KC_HTTPS_PORT                 = tostring(var.keycloak_config.https_port)
              KC_HTTPS_CERTIFICATE_FILE     = "${local.tls_mount}/tls.crt"
              KC_HTTPS_CERTIFICATE_KEY_FILE = "${local.tls_mount}/tls.key"
              KC_HTTP_ENABLED               = "false"
              KC_CACHE                      = "local"
              KC_HEALTH_ENABLED             = "true"
              KC_METRICS_ENABLED            = "true"
              KC_HTTP_MANAGEMENT_PORT       = tostring(var.keycloak_config.management_port)
            }
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env" {
            for_each = {
              KC_BOOTSTRAP_ADMIN_USERNAME = local.credential_env.admin_user
              KC_BOOTSTRAP_ADMIN_PASSWORD = local.credential_env.admin_password
              KC_DB_USERNAME              = local.credential_env.db_user
              KC_DB_PASSWORD              = local.credential_env.db_password
            }
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name = env.value.name
                  key  = env.value.key
                }
              }
            }
          }

          port {
            name           = "https"
            container_port = var.keycloak_config.https_port
          }
          port {
            name           = "management"
            container_port = var.keycloak_config.management_port
          }

          # The first start builds the server, which takes minutes on a small node.
          startup_probe {
            http_get {
              path   = "/health/started"
              port   = var.keycloak_config.management_port
              scheme = "HTTPS"
            }
            period_seconds    = 10
            failure_threshold = 60
          }

          readiness_probe {
            http_get {
              path   = "/health/ready"
              port   = var.keycloak_config.management_port
              scheme = "HTTPS"
            }
            period_seconds = 10
          }

          liveness_probe {
            http_get {
              path   = "/health/live"
              port   = var.keycloak_config.management_port
              scheme = "HTTPS"
            }
            period_seconds = 20
          }

          volume_mount {
            name       = "tls"
            mount_path = local.tls_mount
            read_only  = true
          }

          security_context {
            run_as_non_root            = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          resources {
            requests = var.keycloak_config.resources.requests
            limits   = var.keycloak_config.resources.limits
          }
        }

        volume {
          name = "tls"
          secret {
            secret_name = var.keycloak_config.tls_secret_name
          }
        }
      }
    }
  }

  timeouts {
    create = "15m"
    update = "15m"
  }
}

resource "kubernetes_service_v1" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = var.keycloak_config.namespace
  }

  spec {
    type         = "ClusterIP"
    external_ips = [var.service_config.external_ip]
    selector     = local.keycloak_labels

    port {
      name        = "https"
      port        = var.service_config.port
      target_port = var.keycloak_config.https_port
      protocol    = "TCP"
    }
  }
}
