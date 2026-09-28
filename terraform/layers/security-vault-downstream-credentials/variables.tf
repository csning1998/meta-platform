
variable "keycloak_admin_user" {
  description = "Keycloak admin username (human-managed)."
  type        = string
  sensitive   = true
}

variable "keycloak_db_user" {
  description = "Keycloak database username (human-managed)."
  type        = string
  sensitive   = true
}
