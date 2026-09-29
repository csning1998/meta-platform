
variable "target_clusters" {
  description = "Map of role to physical cluster names from SSoT."
  type        = map(string)
}

variable "primary_role" {
  description = "Primary role key within target_clusters."
  type        = string
}

variable "wipe_spire_state" {
  description = "Deletes the SPIRE Server datastore and CA keys on the next apply, forcing a fresh trust domain. Never true by default: a routine OS-disk rebuild MUST preserve the existing trust chain. Set true only for a deliberate greenfield reset, then revert to false before the next apply."
  type        = bool
  default     = false
}

variable "service_config" {
  description = "Compute topology per role for SPIRE Server (Parent) service."
  type = map(object({
    role            = string
    network_tier    = optional(string, "default")
    base_image_path = string
    nodes = map(object({
      ip_suffix            = number
      vcpu                 = number
      ram_size             = number
      os_disk_capacity_gib = optional(number)
      extra_networks       = optional(map(string), {})
    }))
  }))
}
