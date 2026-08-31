
variable "bastion_vault_endpoint" {
  description = "The address of the bootstrap dev Vault"
  type        = string
  default     = "https://172.16.0.1:8200"
}
