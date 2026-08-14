
variable "target_cluster_name" {
  description = "The physical cluster name target to deploy the service on, retrieved directly from the SSoT mapping."
  type        = string
}

variable "storage_pool_name" {
  description = "Libvirt storage pool name for the Talos node disks."
  type        = string
}

variable "node_config" {
  description = "Configuration for Talos load balancer nodes (resources and IP suffix)."
  type = map(object({
    ip_suffix = number
    vcpu      = number
    ram       = number
  }))
}

variable "talos_version" {
  description = "Talos release deployed by this cluster, e.g. v1.13.8. MUST match the release under packer/output/talos-<version>/, which supplies the boot ISO."
  type        = string
}

variable "talos_kubernetes_version" {
  description = "Target Kubernetes version deployed by the Talos cluster (e.g., v1.32.0). Supplies helm_template kube_version to override the v1.20.0 provider default and satisfy Cilium chart constraints (v1.21.0-0 minimum)."
  type        = string
}

variable "cilium_chart_version" {
  description = "Cilium Helm chart version to render for cluster.inlineManifests."
  type        = string
}

variable "kubeprism_port" {
  description = "Port on which Talos binds KubePrism, its per-node API server load balancer. The default of 7445 applies unless machine.features.kubePrism.port overrides it, and both settings MUST agree for a kube-proxy-free Cilium to reach the API server."
  type        = number
  default     = 7445
}
