
variable "vault_agent_lease_ttl" {
  description = "Lease TTL for Vault Agent auto-renewed certificates issued from the production pki_int."
  type        = string
  default     = "24h"
}
