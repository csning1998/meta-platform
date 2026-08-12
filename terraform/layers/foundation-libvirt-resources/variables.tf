
variable "domain_suffix" {
  description = "Root domain across all consumer projects, used to derive DNS SANs."
  type        = string
}

variable "vault_kv_namespace" {
  description = "Vault KV mount-relative namespace prefix for all service component credential paths."
  type        = string
  default     = "meta-platform"

  validation {
    condition     = length(var.vault_kv_namespace) > 0 && !startswith(var.vault_kv_namespace, "/") && !endswith(var.vault_kv_namespace, "/")
    error_message = "vault_kv_namespace must be non-empty and must not start or end with '/'."
  }
}

variable "global_pki_identity" {
  description = "Global PKI identity settings. Defines the legal identity of the infrastructure."
  type = object({
    root_ca_common_name         = string
    intermediate_ca_common_name = string
    mount_path                  = string
  })

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.global_pki_identity.mount_path))
    error_message = "mount_path must contain only alphanumeric characters, underscores, and hyphens, since it is interpolated directly into Vault policy paths."
  }
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

variable "service_catalog" {
  description = "The Single Source of Truth (SSoT) for all services, component, ingress, and dependencies, passed through to the service_catalog module for validation."
  type = map(object({
    owner        = string
    project_code = string
    stage        = string

    components = map(object({
      provider    = string
      runtime     = string
      cidr_index  = number
      tags        = optional(list(string), [])
      node_groups = optional(list(string), [])
      ip_range = object({
        start_ip = number
        end_ip   = number
      })
      ports = optional(map(object({
        frontend_port            = number
        backend_port             = number
        health_check_type        = optional(string, "tcp")
        health_check_http_path   = optional(string, "/")
        health_check_http_expect = optional(string, "status 200")
        health_check_ssl         = optional(bool, false)
        health_check_sni         = optional(string)
        health_check_port        = optional(number)
        send_proxy_v2            = optional(bool, false)
      })), {})
      data_disks = optional(list(object({
        name_suffix  = string
        capacity_gib = optional(number, 20)
      })), [])
      ingress = optional(map(object({
        subdomains  = list(string)
        node_groups = optional(list(string), [])
      })), {})
      oidc_client = optional(object({
        name          = string
        redirect_path = string
      }), null)
    }))
  }))
}
