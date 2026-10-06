
output "inline_manifests" {
  description = "Rendered manifests for cluster.inlineManifests, keyed by manifest name. The gateway-api entry exists when the Gateway API is enabled."
  value = merge(
    { cilium = data.helm_template.cilium.manifest },
    local.gateway_api_enabled ? { "gateway-api" = data.http.gateway_api_crds[0].response_body } : {}
  )
}

output "hubble_tls_domains" {
  description = "Domains which the PKI role of the ClusterIssuer MUST allow for the Hubble mTLS certificates. Empty when Hubble is disabled."
  value       = var.hubble_config.enabled ? local.hubble_tls_domains : []
}

output "hubble_tls_certificates" {
  description = "Hubble mTLS certificates which the caller MUST issue with a P-256 key, keyed by the Secret name which the chart mounts. Empty when Hubble is disabled."
  value = var.hubble_config.enabled ? {
    for name, cert in local.hubble_tls_certificates : name => {
      namespace   = "kube-system"
      common_name = cert.common_name
      dns_names   = [cert.common_name]
      usages      = cert.usages
    }
  } : {}
}
