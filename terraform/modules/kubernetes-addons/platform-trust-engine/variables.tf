
variable "api_server_connection" {
  description = "Kubernetes API server connection parameters for Vault TokenReview callback authentication."
  type = object({
    host    = string
    ca_cert = string
  })
}

variable "vault_config" {
  description = "Target Vault endpoint and Kubernetes authentication backend mount path."
  type = object({
    address   = string
    auth_path = string
    ca_cert   = optional(string, "")
  })
}

variable "issuer_config" {
  description = "ClusterIssuer specification and corresponding Vault PKI role configurations."
  type = object({
    name            = string # ClusterIssuer name in Kubernetes.
    namespace       = string # Namespace of the issuer ServiceAccount and its token Secret.
    vault_role_name = string # Vault Kubernetes auth role and PKI role name.
    pki_mount_path  = string # PKI engine mount path in Vault.
    issue_path      = string # "issue" or "sign".
  })
}

variable "reviewer_service_account" {
  description = "Dedicated ServiceAccount parameters for Vault token reviewer delegation."
  type = object({
    name      = string
    namespace = string
  })
  default = {
    name      = "vault-reviewer"
    namespace = "default"
  }
}
