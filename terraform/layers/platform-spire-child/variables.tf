
variable "node_config" {
  description = "Hardware resources and IP offsets for Talos control plane nodes matching service catalog allocations."
  type = map(object({
    ip_suffix = number
    vcpu      = number
    ram       = number
  }))
}

variable "talos_version" {
  description = "Talos OS version. MUST match the local Packer boot ISO artifact."
  type        = string
}

variable "talos_kubernetes_version" {
  description = "Target Kubernetes version used for Talos machine config and Cilium Helm chart validation."
  type        = string
}

variable "cilium_chart_version" {
  description = "Cilium Helm chart version to render for cluster.inlineManifests."
  type        = string
}

variable "kubeprism_port" {
  description = "Node-local Talos KubePrism load balancer port required for kube-proxy-free CNI API server routing."
  type        = number
  default     = 7445
}
