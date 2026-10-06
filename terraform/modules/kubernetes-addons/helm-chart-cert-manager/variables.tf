
variable "helm_config" {
  description = "Helm chart render parameters. The chart_repository is the OCI repository which holds the chart, for example the Harbor Origin project of the replicated charts. The kubernetes_version overrides the provider default for the chart constraint check."
  type = object({
    chart_repository   = string
    version            = string
    kubernetes_version = string
    namespace          = optional(string, "cert-manager")
  })
}
