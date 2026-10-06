
variable "api_server_connection" {
  description = "Kubernetes API server address and CA certificate, which Vault calls for TokenReview."
  type = object({
    host    = string
    ca_cert = string
  })
}

variable "vault_auth_path" {
  description = "Mount path of the Vault Kubernetes auth backend which validates the ServiceAccount tokens of this cluster."
  type        = string
}

variable "reviewer_service_account" {
  description = "ServiceAccount whose token Vault presents to the TokenReview API."
  type = object({
    name      = optional(string, "vault-reviewer")
    namespace = string
  })
}
