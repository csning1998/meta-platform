
# SSoT metadata inputs, nested by service name then component name.
variable "global_topology_identity" {
  description = "SSoT topology identity map from foundation-metadata."
  type = map(map(object({
    cluster_name      = string
    stage             = string
    storage_pool_name = string
    bridge_name_host  = string
    bridge_name_nat   = string
    node_name_prefix  = string
    ansible_inventory = string
    ssh_config        = string
    groups = map(object({
      node_name_prefix = string
    }))
  })))
}

variable "global_topology_network" {
  description = "SSoT topology network map from foundation-metadata."
  type = map(map(object({
    segment_key     = string
    cidr_block      = string
    nat_gateway     = string
    nat_cidr_block  = string
    nat_cidr_index  = number
    interface_alias = string
    vrid            = number
    runtime         = string
    mac_address     = string
    node_ips        = list(string)
    vip             = string
    tags            = list(string)
    ip_range = object({
      start_ip = number
      end_ip   = number
    })
    nat_dhcp = object({
      start = string
      end   = string
    })
    ports = map(object({
      frontend_port            = number
      backend_port             = number
      health_check_type        = string
      health_check_http_path   = string
      health_check_http_expect = string
      health_check_ssl         = bool
      health_check_sni         = optional(string)
      health_check_port        = optional(number)
      send_proxy_v2            = bool
    }))
  })))
}

variable "global_pki_map" {
  description = "PKI role map from foundation-metadata."
  type = map(object({
    key         = string
    role_name   = string
    ttl_stage   = string
    has_ingress = bool
    dns_san     = list(string)
    ou          = list(string)
    auth_config = object({
      method       = string
      path         = string
      approle_path = string
    })
    oidc_client = optional(object({
      name          = string
      redirect_path = string
      client_id     = string
    }), null)
  }))
}

variable "global_network_baseline" {
  description = "Global network baseline parameters (MSS, MTU, Node Exporter port) from foundation-metadata."
  type = object({
    global_mss         = number
    global_mtu         = number
    node_exporter_port = number
  })
}

variable "infrastructure_map" {
  description = "Physical network infrastructure map from platform-cilium-frontend handover."
  type = map(object({
    network = object({
      hostonly = object({
        bridge_name = string
        cidr        = string
        gateway     = string
        mtu         = number
        name        = string
        prefix      = number
      })
      nat = object({
        bridge_name = string
        cidr        = string
        gateway     = string
        mtu         = number
        name        = string
        prefix      = number
        stage       = string
        dhcp = object({
          start = string
          end   = string
        })
      })
    })
    lb_config = object({
      vip            = string
      vrid           = number
      interface_name = string
      tags           = list(string)
      ports = map(object({
        frontend_port            = number
        backend_port             = number
        health_check_type        = string
        health_check_http_path   = string
        health_check_http_expect = string
        health_check_ssl         = bool
        health_check_sni         = optional(string)
        health_check_port        = optional(number)
        send_proxy_v2            = bool
      }))
    })
    backend_servers = list(object({
      ip   = string
      name = string
    }))
  }))
}

# Vault integration inputs. These are optional and only required for 30-tier layers featuring Vault Agent integration.
variable "prod_vault_svc_vip" {
  description = "Production Vault VIP for prod_vault_endpoint construction. Required for layers with Vault Agent integration."
  type        = string
  default     = null
}

variable "security_pki_outputs" {
  description = "The `security_pki_outputs` variable MUST conform strictly to the output schema of `security-pki`. Any attribute mismatch causes object type conversion failure during Terraform evaluation."
  type = object({
    workload_identities_approle = map(object({
      role_id   = string
      role_name = string
      auth_path = string
    }))
    prod_pki_configuration = object({
      path = string
      leaf_roles = map(object({
        id              = string
        name            = string
        allowed_domains = list(string)
      }))
      lease_durations = object({
        default = string
        max     = string
        agent   = string
      })
    })
    bastion_pki_chain_b64 = object({
      path        = string
      content_b64 = string
    })
    prod_pki_issuer_cert_b64 = string
  })
  default = null
}

# Targeting
variable "target_clusters" {
  description = "Map of role to physical cluster name from SSoT."
  type        = map(string)

  validation {
    condition     = length(var.target_clusters) > 0
    error_message = "target_clusters must contain at least one entry."
  }
}

variable "primary_role" {
  description = "Primary role key within target_clusters."
  type        = string
}

variable "service_config" {
  description = "Compute topology per role. Keys must match target_clusters keys."
  type = map(object({
    role            = string
    network_tier    = optional(string, "default")
    base_image_path = string
    nodes = map(object({
      ip_suffix            = number
      vcpu                 = number
      ram_size             = number
      os_disk_capacity_gib = optional(number)
      cpu_mode             = optional(string, null)
      attached_volumes = optional(list(object({
        pool   = string
        volume = string
      })), [])
    }))
  }))
}

variable "guest_vm_data" {
  description = "Raw VM credential key-value pairs from Vault secret."
  type        = map(string)
  sensitive   = true
}
