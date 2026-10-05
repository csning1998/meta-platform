
variable "target_clusters" {
  description = "Map of role to physical cluster names from SSoT."
  type        = map(string)
}

variable "primary_role" {
  description = "Primary role key within target_clusters."
  type        = string
}

variable "service_config" {
  description = "Compute topology per role for Keycloak service."
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
    }))
  }))
}

variable "node_config" {
  description = "Hardware resources and IP offsets for Talos control plane nodes. Read when the runtime of the component in the service catalog is a Kubernetes native runtime."
  type = map(object({
    ip_suffix = number
    vcpu      = number
    ram       = number
  }))
  default = {}
}

variable "volume_config" {
  description = "Talos user volume which formats the data disk at device and mounts the disk at /var/mnt/<name>."
  type = object({
    name   = string
    device = optional(string, "/dev/vdb")
  })
  default = {
    name = "keycloak-data"
  }
}

variable "talos_config" {
  description = "Talos settings: the Talos release, which MUST match the boot ISO under packer/output/talos-<version>/, the Kubernetes version, the KubePrism port, and the Gateway API CRD release pinned by digest. A null gateway_api disables the Gateway API. Required for a Kubernetes native runtime."
  type = object({
    talos_version      = string
    kubernetes_version = string
    kubeprism_port     = optional(number, 7445)
    gateway_api = optional(object({
      version = string
      sha256  = string
    }))
  })
  default = null
}

variable "helm_chart_version" {
  description = "Helm chart versions rendered into cluster.inlineManifests. Required for a Kubernetes native runtime."
  type = object({
    cilium           = string
    cert_manager     = string
    external_secrets = string
  })
  default = null
}
