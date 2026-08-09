
variable "vault_agent_lease_ttl" {
  description = "Lease TTL for Vault Agent auto-renewed certificates issued from the production pki_int."
  type        = string
  default     = "24h"
}

variable "vault_workload_identity_module" {
  description = "Source URL and version constraint for `vault-workload-identity` module in GitLab Terraform Module Registry."
  type = object({
    source  = string
    version = string
  })
  const = true
}

variable "vault_pki_setup_module" {
  description = "Source URL and version constraint for `vault-pki-setup` module in GitLab Terraform Module Registry."
  type = object({
    source  = string
    version = string
  })
  const = true
}
