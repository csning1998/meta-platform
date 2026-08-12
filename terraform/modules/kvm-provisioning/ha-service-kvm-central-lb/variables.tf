
variable "ansible_root_path" {
  description = "Absolute path to the consuming repository's ansible/ directory, supplied by the calling layer via path.root. A module-relative path.module lookup breaks once this module is fetched from the Terraform Module Registry."
  type        = string
}

variable "scripts_root_path" {
  description = "Absolute path to the consuming repository's scripts/ directory, supplied by the calling layer via path.root. A module-relative path.module lookup breaks once this module is fetched from the Terraform Module Registry."
  type        = string
}

variable "svc_identity" {
  description = "The SSoT identity object for this load balancer cluster."
  type = object({
    service_name      = string
    cluster_name      = string
    node_name_prefix  = string
    ansible_inventory = string
    ssh_config        = string
    domain_suffix     = string
  })
}

variable "topology_cluster" {
  description = "Standardized compute topology configuration for Load Balancer HA Cluster."
  type = object({

    cluster_name      = string
    storage_pool_name = string

    load_balancer_config = object({
      nodes = map(object({
        base_image_path = string
        vcpu            = number
        ram             = number
        ip_suffix       = number
      }))
    })
  })

  # At least one Load Balancer Class node
  validation {
    condition     = length(var.topology_cluster.load_balancer_config.nodes) > 0
    error_message = "High Availability architecture requires at least one Load Balancer Class node."
  }

  # Load Balancer Node specification (vCPU >= 2, RAM >= 384MiB)
  validation {
    condition = alltrue([
      for k, node in var.topology_cluster.load_balancer_config.nodes :
      node.vcpu >= 2 && node.ram >= 384
    ])
    error_message = "Load Balancer nodes require at least 2 vCPUs and 384MB RAM."
  }
}

variable "svc_network_map" {
  description = "Pure MECE mapping of calculated network attributes (from foundation-metadata)."
  type = map(object({
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
  }))
}

variable "network_service_segments" {
  description = "List of network segments (Infrastructure creation only)."
  type = list(object({
    name           = string
    bridge_name    = string
    interface_name = string
    tags           = optional(list(string))
    cidr           = optional(string)
    vrid           = optional(number)
    vip            = optional(string)
    runtime        = optional(string)
    mtu            = optional(number)
    mss            = optional(number)
    node_ips       = map(string)

    ports = map(object({
      frontend_port            = number
      backend_port             = number
      health_check_type        = optional(string, "tcp")
      health_check_http_path   = optional(string, "/")
      health_check_http_expect = optional(string, "")
      health_check_ssl         = optional(bool, false)
      health_check_sni         = optional(string)
      health_check_port        = optional(number)
      send_proxy_v2            = optional(bool, false)
    }))

    backend_servers = list(object({
      name = string
      ip   = string
    }))
  }))
}

variable "security_pki_bundle_b64" {
  description = "PKI certificates passed from foundation-metadata via foundation-network"
  type = object({
    ca_cert_b64        = string
    haproxy_bundle_b64 = string
  })
  default = null
}

variable "network_infrastructure_map" {
  description = "Standardized infrastructure network configuration."
  type = map(object({
    nat = object({
      name        = string
      bridge_name = string
      gateway     = string
      prefix      = number
      dhcp = optional(object({
        start = string
        end   = string
      }))
      mtu = number
    })
    hostonly = object({
      name        = string
      bridge_name = string
      gateway     = string
      prefix      = number
      mtu         = number
    })
    access_scope = optional(string)
  }))

  validation {
    condition = alltrue([
      for k, v in var.network_infrastructure_map :
      can(cidrhost("${v.nat.gateway}/${v.nat.prefix}", 0)) &&
      can(cidrhost("${v.hostonly.gateway}/${v.hostonly.prefix}", 0))
    ])
    error_message = "All network CIDRs must be valid."
  }
}

variable "ansible_generic_config" {
  description = "Consolidated Ansible configuration including template and extra variables."
  type = object({
    template_vars = any
    extra_vars    = any
  })
  default = {
    template_vars = {}
    extra_vars    = {}
  }
}

# Credentials Injection
variable "credentials_vm" {
  description = "System level credentials (ssh user, password, keys)"
  sensitive   = true
  type = object({
    username             = string
    password             = string
    ssh_public_key_path  = string
    ssh_private_key_path = string
  })
}

variable "credentials_application" {
  description = "Map of application credentials passed as Ansible extra_vars. Individual keys are unparsed by this module."
  sensitive   = true
  type        = map(string)

  validation {
    condition = alltrue([
      for k in ["haproxy_stats_user", "haproxy_stats_pass", "keepalived_auth_pass"] :
      contains(keys(var.credentials_application), k)
    ])
    error_message = "Map must contain `haproxy_stats_user`, `haproxy_stats_pass`, and `keepalived_auth_pass` for `shared_load_balancer` role template rendering."
  }
}
