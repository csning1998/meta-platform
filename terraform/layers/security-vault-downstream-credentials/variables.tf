
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

variable "guest_vm_sync_version" {
  description = "Version of the replicated guest VM secret. Raising the value rewrites the Downstream copy from the Bastion Vault, because Terraform does not track the content of a write only attribute."
  type        = number
  default     = 1
}
