
# ServiceAccount provides system:auth-delegator RBAC for Vault TokenReview API callbacks.
resource "kubernetes_service_account_v1" "vault_reviewer" {
  metadata {
    name      = var.reviewer_service_account.name
    namespace = var.reviewer_service_account.namespace
  }
}

resource "kubernetes_cluster_role_binding_v1" "vault_reviewer" {
  metadata {
    name = var.reviewer_service_account.name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vault_reviewer.metadata[0].name
    namespace = kubernetes_service_account_v1.vault_reviewer.metadata[0].namespace
  }
}

# Long-lived ServiceAccount token ensures deterministic token reviewer authentication from external Vault.
resource "kubernetes_secret_v1" "vault_reviewer_token" {
  metadata {
    name      = var.reviewer_service_account.name
    namespace = var.reviewer_service_account.namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.vault_reviewer.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}

resource "vault_kubernetes_auth_backend_config" "config" {
  backend                = var.vault_config.auth_path
  kubernetes_host        = var.api_server_connection.host
  kubernetes_ca_cert     = var.api_server_connection.ca_cert
  token_reviewer_jwt     = kubernetes_secret_v1.vault_reviewer_token.data["token"]
  disable_iss_validation = true
}

# Issuer ServiceAccount establishes workload identity for cert-manager Vault PKI issuance authentication.
resource "kubernetes_service_account_v1" "issuer" {
  metadata {
    name      = var.issuer_config.name
    namespace = var.issuer_config.namespace
  }
}

resource "kubernetes_secret_v1" "issuer_token" {
  metadata {
    name      = var.issuer_config.name
    namespace = var.issuer_config.namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.issuer.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}
