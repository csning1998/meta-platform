
# Bridges host-level Bastion Vault authority with in-cluster cert-manager and External Secrets Operator runners.
locals {
  trust         = local.state.platform_cilium_frontend.in_cluster_trust
  bastion_vault = local.state.foundation_vault_bastion.bastion_vault

  bastion_vault_config = {
    address = local.bastion_vault.endpoint
    ca_cert = file(local.bastion_vault.listener_ca_cert_path)
  }

  # Derives unauthenticated VIP and cluster CA facts directly to bypass ephemeral kubeconfig limitations.
  api_server_callback = {
    host    = "https://${local.infrastructure_map[local.cilium_cluster_name].lb_config.vip}:6443"
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
    namespace = local.trust.cluster_issuer.namespace
  }

  lifecycle {
    postcondition {
      condition     = try(self.object.status.availableReplicas, 0) >= 1
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
    namespace = local.trust.external_secrets.namespace
  }

  lifecycle {
    postcondition {
      condition     = try(self.object.status.availableReplicas, 0) >= 1
      error_message = "The External Secrets Operator webhook is not available yet. Apply again after the Deployment reports an available replica."
    }
  }
}

module "platform_trust_engine" {
  source     = "../../modules/kubernetes-addons/platform-trust-engine"
  depends_on = [data.kubernetes_resource.cert_manager_webhook]

  api_server_connection = local.api_server_callback
  vault_config = {
    address   = local.bastion_vault_config.address
    auth_path = local.trust.cluster_issuer.auth_path
    ca_cert   = local.bastion_vault_config.ca_cert
  }
  issuer_config = {
    name            = local.trust.cluster_issuer.name
    namespace       = local.trust.cluster_issuer.namespace
    vault_role_name = local.trust.cluster_issuer.role_name
    pki_mount_path  = local.trust.cluster_issuer.pki_mount_path
    issue_path      = local.trust.cluster_issuer.issue_path
  }
}

module "platform_cluster_issuer" {
  source = "../../modules/kubernetes-addons/platform-cluster-issuer"

  vault_config = {
    address   = local.bastion_vault_config.address
    auth_path = local.trust.cluster_issuer.auth_path
    ca_cert   = local.bastion_vault_config.ca_cert
  }
  issuer_config = {
    name            = local.trust.cluster_issuer.name
    vault_role_name = local.trust.cluster_issuer.role_name
    pki_mount_path  = local.trust.cluster_issuer.pki_mount_path
    issue_path      = local.trust.cluster_issuer.issue_path
  }
  token_secret = {
    name      = module.platform_trust_engine.cluster_issuer.token_secret_name
    namespace = module.platform_trust_engine.cluster_issuer.token_secret_namespace
  }
}

resource "kubernetes_service_account_v1" "external_secrets_vault" {
  depends_on = [ephemeral.talos_cluster_health.this]

  metadata {
    name      = local.trust.external_secrets.service_account
    namespace = local.trust.external_secrets.namespace
  }
}

resource "kubernetes_manifest" "bastion_vault_store" {
  depends_on = [data.kubernetes_resource.external_secrets_webhook]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "bastion-vault" }
    spec = {
      provider = {
        vault = {
          server   = local.bastion_vault_config.address
          path     = "secret"
          version  = "v2"
          caBundle = base64encode(local.bastion_vault_config.ca_cert)
          auth = {
            kubernetes = {
              mountPath = local.trust.cluster_issuer.auth_path
              role      = local.trust.external_secrets.role_name
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
