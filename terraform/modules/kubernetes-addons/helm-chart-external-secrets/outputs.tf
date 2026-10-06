
# The Helm template does not render the namespace, hence the leading Namespace document.
output "inline_manifests" {
  description = "Rendered manifest for cluster.inlineManifests, keyed by manifest name."
  value = {
    "external-secrets" = "apiVersion: v1\nkind: Namespace\nmetadata:\n  name: ${var.helm_config.namespace}\n---\n${data.helm_template.external_secrets.manifest}"
  }
}
