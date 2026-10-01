
variable "target_clusters" {
  description = "Map of role to physical cluster names from SSoT."
  type        = map(string)
}

variable "primary_role" {
  description = "Primary role key within target_clusters."
  type        = string
}

variable "bastion_vault_endpoint" {
  description = "The address of the Vault server."
  type        = string
  default     = "https://172.16.0.1:8200"
}

variable "service_config" {
  description = "Compute topology per role for Vault Core service."
  type = map(object({
    role            = string
    network_tier    = optional(string, "default")
    base_image_path = string
    nodes = map(object({
      ip_suffix            = number
      vcpu                 = number
      ram_size             = number
      os_disk_capacity_gib = optional(number)
    }))
  }))
}

variable "pki_identity" {
  description = "Identity of the intermediate CA which the Downstream Vault holds: the common name of the CA and the mount path of the PKI engine."
  type = object({
    intermediate_ca_common_name = string
    intermediate_mount_path     = string
  })

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.pki_identity.intermediate_mount_path))
    error_message = "The intermediate_mount_path value MUST contain only alphanumeric characters, underscores, and hyphens for Vault policy path interpolation."
  }
}
