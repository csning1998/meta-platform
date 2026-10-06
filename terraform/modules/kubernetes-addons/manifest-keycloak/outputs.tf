
output "server" {
  description = "The Keycloak Deployment, which reports ready once the rollout passes the readiness probe, and the Service which publishes the server."
  value = {
    deployment_name = kubernetes_deployment_v1.keycloak.metadata[0].name
    service_name    = kubernetes_service_v1.keycloak.metadata[0].name
    external_ip     = var.service_config.external_ip
    port            = var.service_config.port
  }
}
