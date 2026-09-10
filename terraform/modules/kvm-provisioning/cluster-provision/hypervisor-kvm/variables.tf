
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
        pool           = string
        volume         = string
        device_name    = optional(string)
        os_disk_format = optional(string, "qcow2")
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

variable "start_domains" {
  description = "Whether created domains boot immediately. Set false for os_disk_format = raw so a calling layer's Ansible role can convert base_image content into the empty raw volume before first boot, then flip this to true in a follow-up apply."
  type        = bool
  default     = true
}

variable "os_disk_format" {
  description = "OS disk volume format for every node in this module call. Defaults to qcow2 (backing_store linked clone from base_image). Set raw for clusters running etcd or another write-latency-sensitive consensus store; raw volumes are declared empty here, with content materialization left to an Ansible role, since raw cannot use a qcow2 backing_store as an overlay."
  type        = string
  default     = "qcow2"

  validation {
    condition     = contains(["raw", "qcow2"], var.os_disk_format)
    error_message = "os_disk_format must be 'raw' or 'qcow2'."
  }
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
