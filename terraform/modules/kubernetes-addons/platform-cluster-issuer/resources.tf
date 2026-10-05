
# Issuer ServiceAccount establishes workload identity for cert-manager Vault PKI issuance authentication.
resource "kubernetes_service_account_v1" "issuer" {
  metadata {
    name      = var.issuer_config.service_account
    namespace = var.issuer_config.namespace
  }
}

resource "kubernetes_secret_v1" "issuer_token" {
  metadata {
    name      = var.issuer_config.service_account
    namespace = var.issuer_config.namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.issuer.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}

# ClusterIssuer requires cert-manager CRD registration prior to manifest evaluation.
resource "kubernetes_manifest" "cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = var.issuer_config.name
    }
    spec = {
      vault = {
        path     = "${var.issuer_config.pki_mount_path}/${var.issuer_config.issue_path}/${var.issuer_config.vault_role_name}"
        server   = var.vault_config.address
        caBundle = base64encode(var.vault_config.ca_cert)
        auth = {
          kubernetes = {
            role      = var.issuer_config.vault_role_name
            mountPath = "/v1/auth/${var.vault_config.auth_path}"
            secretRef = {
              name = kubernetes_secret_v1.issuer_token.metadata[0].name
              key  = "token"
            }
          }
        }
      }
    }
  }
}
