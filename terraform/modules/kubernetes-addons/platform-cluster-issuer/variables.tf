
variable "vault_config" {
  description = "Connection parameters for the Vault PKI certificate authority."
  type = object({
    address   = string
    auth_path = string
    ca_cert   = string
  })
}

variable "issuer_config" {
  description = "ClusterIssuer naming and corresponding Vault PKI role mapping parameters."
  type = object({
    name            = string
    vault_role_name = string
    pki_mount_path  = string
    issue_path      = string
  })
}

variable "token_secret" {
  description = "ServiceAccount secret coordinates providing Vault authentication credentials for the issuer."
  type = object({
    name      = string
    namespace = string
  })
}
