variable "name" {
  description = "Logical name of the workload identity, matching the AppRole role name"
  type        = string
}

variable "approle_mount_path" {
  description = "Mount path of the AppRole auth backend"
  type        = string
}

variable "vault_role_name" {
  description = "PKI role name defined by vault-pki-setup that this identity is scoped to"
  type        = string
}

variable "pki_mount_path" {
  description = "Mount path of the PKI secrets engine"
  type        = string
}

variable "token_ttl" {
  description = "TTL of the generated AppRole token"
  type        = number
  default     = 3600
}

variable "token_max_ttl" {
  description = "Max TTL of the generated AppRole token"
  type        = number
  default     = 86400
}

variable "extra_policy_hcl" {
  description = "Additional Vault policy capabilities merged into the generated ACL policy"
  type = map(object({
    capabilities = list(string)
  }))
  default = {}
}
