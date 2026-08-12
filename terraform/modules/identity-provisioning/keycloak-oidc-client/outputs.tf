
output "clients" {
  description = "Provisioned Keycloak OIDC clients, indexed by service name."
  value       = keycloak_openid_client.clients
}
