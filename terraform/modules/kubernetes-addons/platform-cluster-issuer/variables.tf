
variable "vault_config" {
  description = "Connection parameters for the Vault PKI certificate authority."
  type = object({
    address   = string
    auth_path = string
    ca_cert   = string
  })
}

variable "issuer_config" {
  description = "ClusterIssuer naming, the ServiceAccount whose token authenticates the issuer to Vault, and the corresponding Vault PKI role mapping."
  type = object({
    name            = string
    namespace       = string
    service_account = string
    vault_role_name = string
    pki_mount_path  = string
    issue_path      = string
  })
}
