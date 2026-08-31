
/**
 * Virtual Machine Configuration
 * Variables defining the specifications and credentials for the VMs.
*/

# Module-level variable definitions

variable "guest_config" {
  description = "All configurations related to the virtual machines being provisioned."
  type = object({
    all_nodes_map = map(object({
      ip                   = string
      vcpu                 = number
      ram_size             = number
      os_disk_capacity_gib = optional(number, 40) # Typically `vda.vda2`
      base_image_path      = string
      network_tier         = string
      cpu_mode             = optional(string, null)

      attached_volumes = optional(list(object({
        pool        = string
        volume      = string
        device_name = optional(string)
      })), [])

      # Specifies pre-existing libvirt networks for secondary interfaces beyond the primary NAT/HostOnly pair. The calling layer SHALL define all target networks.
      # Map key: Target libvirt network name.
      # Map value: Guest static CIDR address assigned to the corresponding target libvirt network.
      extra_networks = optional(map(string), {})
    }))
  })
}

variable "create_networks" {
  description = "Whether to create libvirt_network resources. Set to false if attaching to existing networks (e.g. created by foundation-network)."
  type        = bool
  default     = true
}

variable "credentials" {
  description = "Access credentials for the virtual machines."
  type = object({
    username            = string
    password            = string
    ssh_public_key_path = string
  })
}

variable "static_routes" {
  description = "Static routes keyed by network_tier. Each entry is the list of routes for nodes in that tier."
  type = map(list(object({
    to     = string
    via    = string
    metric = number
  })))
  default = {}
}

variable "libvirt_infrastructure" {
  description = "All configurations for Libvirt-managed networks and storage."
  type = map(object({
    network = object({
      nat = object({
        name_network = string
        name_bridge  = string
        mode         = string
        ips = object({
          address = string
          prefix  = number
          dhcp = optional(object({
            start = optional(string)
            end   = optional(string)
          }))
        })
        mtu = number
      })
      hostonly = object({
        name_network = string
        name_bridge  = string
        mode         = string
        ips = object({
          address = string
          prefix  = number
          dhcp = optional(object({
            start = optional(string)
            end   = optional(string)
          }))
        })
        mtu = number
      })
    })
    storage_pool_name = string
  }))
}
