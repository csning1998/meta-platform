
# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 5.
variable "name" {
  description = "Sets the JWT authentication backend role identifier for the target workload identity"
  type        = string
}

variable "auth_backend_path" {
  description = "Mount path of the shared vault_jwt_auth_backend resource"
  type        = string
}

variable "spiffe_id" {
  description = "Exact SPIFFE ID evaluated against the JWT-SVID sub claim"
  type        = string
}

variable "audience" {
  description = "Required aud claim value validated during JWT-SVID authentication"
  type        = string
  default     = "vault"
}

variable "vault_role_name" {
  description = "Name of the Vault PKI role defined for certificate issuance"
  type        = string
}

variable "pki_mount_path" {
  description = "Mount path of the targeted PKI secrets engine"
  type        = string
}

variable "token_ttl" {
  description = "TTL in seconds for tokens issued upon JWT authentication"
  type        = number
  default     = 3600
}

variable "token_max_ttl" {
  description = "Maximum TTL in seconds for tokens issued upon JWT authentication"
  type        = number
  default     = 86400
}

variable "extra_policy_paths" {
  description = "Additional Vault ACL policy capabilities merged into the generated policy definition"
  type = map(object({
    capabilities = list(string)
  }))
  default = {}
}
