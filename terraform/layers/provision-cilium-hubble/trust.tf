
# Bridges the Downstream Vault with the in-cluster cert-manager and External Secrets Operator of the Cilium cluster.
locals {
  downstream_vault = {
    address = local.state.security_vault_downstream_tenants.downstream_vault_endpoint
    ca_cert = file(local.state.security_vault_downstream_tenants.downstream_vault_ca_cert_path)
  }

  # Derives unauthenticated VIP and cluster CA facts directly to bypass ephemeral kubeconfig limitations.
  cilium_hubble_api_server_callback = {
    host    = "https://${local.foundation_infrastructure_map[local.cilium_cluster_name].lb_config.vip}:6443"
    ca_cert = data.kubernetes_config_map_v1.root_ca.data["ca.crt"]
  }
}

# Every read of the Kubernetes API waits for the health check, since the OpenAPI request of the provider times out on a converging API server.
data "kubernetes_config_map_v1" "root_ca" {
  depends_on = [ephemeral.talos_cluster_health.this]

  metadata {
    name      = "kube-root-ca.crt"
    namespace = "kube-system"
  }
}

# Guards against early CRD admission failures before operator webhook endpoints achieve readiness.
data "kubernetes_resource" "cert_manager_webhook" {
  depends_on = [ephemeral.talos_cluster_health.this]

  api_version = "apps/v1"
  kind        = "Deployment"

  metadata {
    name      = "cert-manager-webhook"
    namespace = local.cilium_hubble_cluster_issuer.namespace
  }

  lifecycle {
    postcondition {
      condition     = coalesce(self.object.status.availableReplicas, 0) >= 1
      error_message = "The cert-manager webhook is not available yet. Apply again after the Deployment reports an available replica."
    }
  }
}

data "kubernetes_resource" "external_secrets_webhook" {
  depends_on = [ephemeral.talos_cluster_health.this]

  api_version = "apps/v1"
  kind        = "Deployment"

  metadata {
    name      = "external-secrets-webhook"
    namespace = local.cilium_hubble_external_secrets.namespace
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
  source     = "../../modules/kubernetes-addons/vault-token-reviewer"
  depends_on = [ephemeral.talos_cluster_health.this]
  providers  = { vault = vault.downstream }

  api_server_connection    = local.cilium_hubble_api_server_callback
  vault_auth_path          = local.cilium_hubble_cluster_issuer.auth_path
  reviewer_service_account = { namespace = local.cilium_hubble_cluster_issuer.namespace }
}

module "platform_cluster_issuer" {
  source     = "../../modules/kubernetes-addons/platform-cluster-issuer"
  depends_on = [data.kubernetes_resource.cert_manager_webhook, module.vault_token_reviewer]

  vault_config = {
    address   = local.downstream_vault.address
    auth_path = module.vault_token_reviewer.vault_auth_path
    ca_cert   = local.downstream_vault.ca_cert
  }
  issuer_config = local.cilium_hubble_cluster_issuer
}

# The Cilium chart mounts these Secrets, and the Hubble server and relay start serving mTLS once cert-manager writes the Secrets.
module "hubble_tls_certificates" {
  source   = "../../modules/kubernetes-addons/platform-certificate"
  for_each = local.state.platform_cilium_hubble.hubble_tls_certificates

  certificate_config = {
    name        = each.key
    namespace   = each.value.namespace
    common_name = each.value.common_name
    dns_names   = each.value.dns_names
    usages      = each.value.usages
  }
  issuer_ref = module.platform_cluster_issuer.cluster_issuer
}

resource "kubernetes_service_account_v1" "external_secrets_vault" {
  depends_on = [ephemeral.talos_cluster_health.this]

  metadata {
    name      = local.cilium_hubble_external_secrets.service_account
    namespace = local.cilium_hubble_external_secrets.namespace
  }
}

resource "kubernetes_manifest" "downstream_vault_store" {
  depends_on = [data.kubernetes_resource.external_secrets_webhook]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "downstream-vault" }
    spec = {
      provider = {
        vault = {
          server   = local.downstream_vault.address
          path     = local.cilium_hubble_external_secrets.kv_mount_path
          version  = "v2"
          caBundle = base64encode(local.downstream_vault.ca_cert)
          auth = {
            kubernetes = {
              mountPath = local.cilium_hubble_cluster_issuer.auth_path
              role      = local.cilium_hubble_external_secrets.role_name
              serviceAccountRef = {
                name      = kubernetes_service_account_v1.external_secrets_vault.metadata[0].name
                namespace = kubernetes_service_account_v1.external_secrets_vault.metadata[0].namespace
              }
            }
          }
        }
      }
    }
  }
}
