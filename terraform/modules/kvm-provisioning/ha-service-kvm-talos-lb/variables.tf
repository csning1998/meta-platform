
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
  description = "Standardized compute topology configuration for the Talos load balancer cluster. Cluster naming comes from svc_identity.cluster_name; this object carries no separate name field."
  type = object({
    storage_pool_name = string

    load_balancer_config = object({
      nodes = map(object({
        vcpu      = number
        ram       = number
        ip_suffix = number
      }))
    })
  })

  validation {
    condition     = length(var.topology_cluster.load_balancer_config.nodes) > 0
    error_message = "High Availability architecture requires at least one Talos node."
  }

  validation {
    condition = alltrue([
      for k, node in var.topology_cluster.load_balancer_config.nodes :
      node.vcpu >= 2 && node.ram >= 2048
    ])
    error_message = "Talos control-plane nodes require at least 2 vCPUs and 2048 MiB RAM."
  }
}

variable "svc_network_map" {
  description = "Pure MECE mapping of calculated network attributes (from foundation-libvirt-resources)."
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
  description = "List of network segments (infrastructure creation only)."
  type = list(object({
    name           = string
    bridge_name    = string
    interface_name = string
    tags           = optional(list(string))
    cidr           = string
    vrid           = number
    node_ips       = map(string)
  }))
}

variable "network_infrastructure_map" {
  description = "Physical NAT and HostOnly network config for the cluster's own segment, keyed by cluster_name."
  type = map(object({
    hostonly = object({
      name        = string
      bridge_name = string
      gateway     = string
      prefix      = number
      mtu         = number
    })
    nat = object({
      name        = string
      bridge_name = string
      gateway     = string
      prefix      = number
      mtu         = number
      dhcp = optional(object({
        start = string
        end   = string
      }))
    })
    access_scope = optional(string)
  }))
}

variable "talos_iso_path" {
  description = "Absolute path to the Talos metal ISO used to bootstrap every node in this cluster."
  type        = string
}

variable "talos_kubernetes_version" {
  description = "Kubernetes version deployed by this Talos cluster, e.g. v1.32.0."
  type        = string
}

variable "cilium_inline_manifest" {
  description = "Rendered Cilium installation manifest, injected via cluster.inlineManifests so Cilium becomes active during bootstrap, before kubectl is reachable and before Harbor exists to serve the chart."
  type        = string
}

variable "bootstrap_timeout" {
  description = "Retry window for the etcd bootstrap RPC. The provider retries internally for this duration, which absorbs the install-to-disk and reboot cycle following configuration delivery. Matches the provider default of 10 minutes."
  type        = string
  default     = "10m"
}

variable "health_timeout" {
  description = "Timeout for talos_cluster_health to observe etcd, Kubernetes, and kubelet convergence, including the Cilium CNI image pull and startup on which kubelet readiness depends."
  type        = string
  default     = "15m"
}

variable "talos_version" {
  description = "Talos release deployed by this cluster, e.g. v1.13.8. Drives the config schema contract and the installer image, and MUST match the release the boot ISO carries."
  type        = string
}
