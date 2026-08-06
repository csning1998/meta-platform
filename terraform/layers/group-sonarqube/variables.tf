
variable "sonarqube_admin_password" {
  description = "Authenticates the sonarqube provider against the self-hosted instance's built-in admin account."
  type        = string
  sensitive   = true
}

variable "vault_token" {
  description = "Authenticates the vault provider against the self-hosted Vault instance."
  type        = string
  sensitive   = true
}
