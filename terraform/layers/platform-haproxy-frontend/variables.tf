
variable "target_components" {
  description = "Map of role to the service and the component of the SSoT catalog. The layer resolves each pair to the cluster name of the foundation topology."
  type = map(object({
    service   = string
    component = string
  }))
}

variable "primary_role" {
  description = "Primary role key within target_components."
  type        = string
}

variable "service_config" {
  description = "Compute topology per role for the HAProxy tier. extra_networks is computed by this layer, not set by the caller."
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
