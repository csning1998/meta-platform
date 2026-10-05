
# The chart renders to a manifest, since Talos applies the manifest at bootstrap before the API server exists.
data "helm_template" "cert_manager" {
  name         = "cert-manager"
  namespace    = var.helm_config.namespace
  chart        = "${var.helm_config.chart_repository}/cert-manager"
  version      = var.helm_config.version
  kube_version = var.helm_config.kubernetes_version

  values = [yamlencode({
    crds            = { enabled = true }
    startupapicheck = { enabled = false }
  })]
}
