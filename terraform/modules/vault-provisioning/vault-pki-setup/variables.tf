
variable "prod_vault_endpoint" {
  description = "Network endpoint address of the target Vault server where the intermediate PKI engine is mounted."
  type        = string
}

variable "pki_settings" {
  description = "Global certificate parameters for generating the downstream intermediate CA."
  type = object({
    intermediate_ca_common_name = string
  })
}

variable "pki_roles" {
  description = "Specification map defining certificate issuance parameters and domain constraints per service role."
  type = map(object({
    name            = string
    auth_method     = string
    auth_path       = string
    allowed_domains = list(string)
    ou              = list(string)
    max_ttl         = number
    ttl             = number
  }))
}

variable "pki_engine_config" {
  description = "Mount path and lease duration parameters for the downstream PKI secrets engine."
  type = object({
    path                      = string
    default_lease_ttl_seconds = number
    max_lease_ttl_seconds     = number
  })
}

variable "bastion_pki_inter_mount_path" {
  description = "Mount path of the upstream Bastion Vault intermediate PKI engine responsible for signing CSRs."
  type        = string
}
