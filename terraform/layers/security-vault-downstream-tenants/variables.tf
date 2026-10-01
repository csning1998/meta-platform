
variable "tenants" {
  description = "Tenant workload definitions mapping SPIFFE identities to JWT auth backend roles and KV/PKI ACL policies."
  type = map(object({
    issuer        = optional(string, "child")
    spiffe_id     = string
    kv_paths      = optional(list(string), [])
    kv_read_paths = optional(list(string), [])
    pki_roles     = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for t in var.tenants : startswith(t.spiffe_id, "spiffe://")])
    error_message = "Every spiffe_id MUST be a full SPIFFE ID."
  }

  validation {
    condition     = alltrue([for t in var.tenants : contains(["parent", "child"], t.issuer)])
    error_message = "The issuer MUST be parent or child."
  }
}
