
# The apply waits for the Ready condition, hence a workload which mounts the Secret starts after the issuance.
resource "kubernetes_manifest" "certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = var.certificate_config.name
      namespace = var.certificate_config.namespace
    }
    spec = {
      secretName  = var.certificate_config.name
      commonName  = var.certificate_config.common_name
      dnsNames    = var.certificate_config.dns_names
      ipAddresses = var.certificate_config.ip_addresses
      usages      = var.certificate_config.usages
      duration    = var.certificate_config.duration
      renewBefore = var.certificate_config.renew_before
      issuerRef   = var.issuer_ref
      # The PKI roles of vault-kubernetes-auth sign only a P-256 key, and every renewal draws a new key.
      privateKey = {
        algorithm      = "ECDSA"
        size           = 256
        rotationPolicy = "Always"
      }
    }
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }
}
