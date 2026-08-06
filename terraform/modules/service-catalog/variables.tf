
variable "domain_suffix" {
  description = "Root domain across all services, used to derive DNS SANs."
  type        = string
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
  description = "The Single Source of Truth (SSoT) for all services, component, ingress, and dependencies, owned by the calling project."
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
    }))
  }))

  # Validate Runtime Enum
  validation {
    condition = alltrue(flatten([
      for s in var.service_catalog : [
        for c in s.components : contains([
          "baremetal", "docker", "podman", "microk8s", "kubeadm", "minikube", "external"
        ], c.runtime)
      ]
    ]))
    error_message = "Component runtime contains invalid values."
  }

  # Validate Provider Enum
  validation {
    condition = alltrue(flatten([
      for s in var.service_catalog : [
        for c in s.components : contains(["kvm", "aws", "gcp", "azure", "vmware"], c.provider)
      ]
    ]))
    error_message = "Component provider must be one of: kvm, aws, gcp, azure, vmware."
  }

  # Validate Stage Enum
  validation {
    condition = alltrue([
      for k, v in var.service_catalog : contains(["production", "staging", "development"], v.stage)
    ])
    error_message = "Service stage must be one of: production, staging, development."
  }

  # Validate CIDR Index Requirements
  validation {
    condition = alltrue(flatten([
      for s in var.service_catalog : [
        for c in s.components : c.cidr_index > 124 && c.cidr_index < 249
      ]
    ]))
    error_message = "Component cidr_index must be in range [125, 248]."
  }

  # Validate Global CIDR Index Uniqueness
  validation {
    condition = length(flatten([
      for s in var.service_catalog : [
        for c in s.components : c.cidr_index
      ]
      ])) == length(distinct(flatten([
        for s in var.service_catalog : [
          for c in s.components : c.cidr_index
        ]
    ])))
    error_message = "Duplicate 'cidr_index' detected! Every component must have a unique CIDR index to avoid network collision."
  }

  # Validate Start IP < End IP
  validation {
    condition = alltrue(flatten([
      for s in var.service_catalog : [
        for c in s.components : c.ip_range.end_ip >= c.ip_range.start_ip
      ]
    ]))
    error_message = "Invalid reservation: 'end_ip' must be greater than or equal to 'start_ip'."
  }

  # Validate Boundary (1-254)
  validation {
    condition = alltrue(flatten([
      for s in var.service_catalog : [
        for c in s.components : c.ip_range.start_ip > 0 && c.ip_range.end_ip < 255
      ]
    ]))
    error_message = "Reservation out of bounds: IPs must be between 1 and 254."
  }

  # Validate Service Key Format (DNS Safe: lowercase, numbers, hyphens)
  validation {
    condition = alltrue([
      for k, v in var.service_catalog : can(regex("^[a-z0-9-]+$", k))
    ])
    error_message = "Service names (keys) must only contain lowercase letters, numbers, and hyphens (DNS safe)."
  }

  # Validate Component Key Format (DNS Safe: lowercase, numbers, hyphens)
  validation {
    condition = alltrue(flatten([
      for k, v in var.service_catalog : [
        for c_k, c_v in v.components : can(regex("^[a-z0-9-]+$", c_k))
      ]
    ]))
    error_message = "Component names (keys) must only contain lowercase letters, numbers, and hyphens (DNS safe)."
  }

  # Validate Composite Key Uniqueness. _flat_catalog concatenates service and component
  # names as "${s_name}-${c_name}" with no delimiter, letting "a-b" plus "c" collide with
  # "a" plus "b-c". The rule above only bounds characters and does not catch this case.
  validation {
    condition = (
      length(flatten([
        for k, v in var.service_catalog : [
          for c_k, c_v in v.components : "${k}-${c_k}"
        ]
        ])) == length(distinct(flatten([
          for k, v in var.service_catalog : [
            for c_k, c_v in v.components : "${k}-${c_k}"
          ]
      ])))
    )
    error_message = "Two (service, component) pairs produce the same composite key after concatenation. Rename one of the colliding service or component names to remove the ambiguity."
  }

  # Validate Project Code Format
  validation {
    condition = alltrue([
      for k, v in var.service_catalog : can(regex("^[a-z0-9]+$", v.project_code))
    ])
    error_message = "Project code must only contain lowercase letters and numbers."
  }

  # Validate Ingress Subdomains Non-Empty
  # Every ingress entry must have at least one valid subdomain to ensure DNS generation.
  validation {
    condition = alltrue(flatten([
      for k, s in var.service_catalog : [
        for c_k, c in s.components : [
          for i_k, i_v in coalesce(c.ingress, {}) : length(i_v.subdomains) > 0
        ]
      ]
    ]))
    error_message = "Every ingress entry must define at least one subdomain."
  }
}
