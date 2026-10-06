
variable "tenants" {
  description = "Tenant workloads, each mapping a SPIFFE ID to a JWT auth role and KV and PKI ACL policies. issuer child binds a workload attested by the SPIRE Child, such as a pod or a VM agent of the Child, and provision-spire-child creates its role. issuer parent binds a workload attested by the SPIRE Parent, and this layer creates its role."
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
