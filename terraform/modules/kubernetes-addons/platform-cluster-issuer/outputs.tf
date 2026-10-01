
output "cluster_issuer" {
  description = "ClusterIssuer reference attributes for consumer certificate manifests."
  value = {
    name  = var.issuer_config.name
    kind  = "ClusterIssuer"
    group = "cert-manager.io"
  }
}
