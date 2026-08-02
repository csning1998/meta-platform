
variable "domain_suffix" {
  description = "Root domain across all consumer projects, used to derive DNS SANs."
  type        = string
}

variable "pki_config" {
  description = "Global PKI identity settings. Defines the legal identity of the infrastructure."
  type = object({
    root_ca_common_name         = string
    intermediate_ca_common_name = string
  })
}

variable "network_baseline" {
  description = "Base network configuration including CIDR, VIP offsets, and MAC prefixes."
  type = object({
    cidr_block         = string
    vip_offset         = number
    node_ip_start      = number
    mac_prefix         = string
    global_mtu         = number
    global_mss         = number
    node_exporter_port = number
  })

  # Validate CIDR Block Format
  validation {
    condition     = can(cidrnetmask(var.network_baseline.cidr_block))
    error_message = "The 'cidr_block' must be a valid IPv4 CIDR range (e.g., 172.16.0.0/16)."
  }

  # Validate MAC Prefix Format. Should be in the format XX:XX:XX (e.g., 52:54:00)
  validation {
    condition     = can(regex("^([0-9a-fA-F]{2}:){2}[0-9a-fA-F]{2}$", var.network_baseline.mac_prefix))
    error_message = "The 'mac_prefix' must be in the format XX:XX:XX (e.g., 52:54:00)."
  }

  # Validate IP Offset Range
  validation {
    condition     = var.network_baseline.vip_offset < 255 && var.network_baseline.node_ip_start < 255
    error_message = "IP offsets must be less than 255 to fit within a /24 subnet."
  }
}
