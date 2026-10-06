# Bridges the Downstream Vault with the in-cluster cert-manager and External Secrets Operator of the Keycloak Talos runtime.

# Every read of the Kubernetes API waits for the health check, since the OpenAPI request of the provider times out on a converging API server.
data "kubernetes_config_map_v1" "root_ca" {
  count = local.is_runtime_talos ? 1 : 0

  depends_on = [ephemeral.talos_cluster_health.this]

  metadata {
    name      = "kube-root-ca.crt"
    namespace = "kube-system"
  }
}

# Guards against early CRD admission failures before the webhook endpoints are ready.
data "kubernetes_resource" "cert_manager_webhook" {
  count = local.is_runtime_talos ? 1 : 0

  depends_on = [ephemeral.talos_cluster_health.this]

  api_version = "apps/v1"
  kind        = "Deployment"

  metadata {
    name      = "cert-manager-webhook"
    namespace = local.keycloak_cluster_issuer.namespace
  }

  lifecycle {
    postcondition {
      condition     = coalesce(self.object.status.availableReplicas, 0) >= 1
      error_message = "The cert-manager webhook is not available yet. Apply again after the Deployment reports an available replica."
    }
  }
}

data "kubernetes_resource" "external_secrets_webhook" {
  count = local.is_runtime_talos ? 1 : 0

  depends_on = [ephemeral.talos_cluster_health.this]

  api_version = "apps/v1"
  kind        = "Deployment"

  metadata {
    name      = "external-secrets-webhook"
    namespace = local.keycloak_external_secrets.namespace
  }

  lifecycle {
    postcondition {
      condition     = coalesce(self.object.status.availableReplicas, 0) >= 1
      error_message = "The External Secrets Operator webhook is not available yet. Apply again after the Deployment reports an available replica."
    }
  }
}

# Vault validates the ServiceAccount tokens of this cluster through the TokenReview API of the cluster.
module "vault_token_reviewer" {
  count = local.is_runtime_talos ? 1 : 0

  source     = "../../modules/kubernetes-addons/vault-token-reviewer"
  depends_on = [ephemeral.talos_cluster_health.this]
  providers  = { vault = vault.downstream }

  api_server_connection    = local.keycloak_api_server_callback
  vault_auth_path          = local.keycloak_cluster_issuer.auth_path
  reviewer_service_account = { namespace = local.keycloak_cluster_issuer.namespace }
}

module "platform_cluster_issuer" {
  count = local.is_runtime_talos ? 1 : 0

  source     = "../../modules/kubernetes-addons/platform-cluster-issuer"
  depends_on = [data.kubernetes_resource.cert_manager_webhook, module.vault_token_reviewer]

  vault_config = {
    address   = local.downstream_vault.address
    auth_path = module.vault_token_reviewer[0].vault_auth_path
    ca_cert   = local.downstream_vault.ca_cert
  }
  issuer_config = local.keycloak_cluster_issuer
}

resource "kubernetes_service_account_v1" "external_secrets_vault" {
  count = local.is_runtime_talos ? 1 : 0

  depends_on = [ephemeral.talos_cluster_health.this]

  metadata {
    name      = local.keycloak_external_secrets.service_account
    namespace = local.keycloak_external_secrets.namespace
  }
}

resource "kubernetes_manifest" "downstream_vault_store" {
  count = local.is_runtime_talos ? 1 : 0

  depends_on = [data.kubernetes_resource.external_secrets_webhook]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "downstream-vault" }
    spec = {
      provider = {
        vault = {
          server   = local.downstream_vault.address
          path     = local.keycloak_external_secrets.kv_mount_path
          version  = "v2"
          caBundle = base64encode(local.downstream_vault.ca_cert)
          auth = {
            kubernetes = {
              mountPath = local.keycloak_cluster_issuer.auth_path
              role      = local.keycloak_external_secrets.role_name
              serviceAccountRef = {
                name      = kubernetes_service_account_v1.external_secrets_vault[0].metadata[0].name
                namespace = kubernetes_service_account_v1.external_secrets_vault[0].metadata[0].namespace
              }
            }
          }
        }
      }
    }
  }
}
