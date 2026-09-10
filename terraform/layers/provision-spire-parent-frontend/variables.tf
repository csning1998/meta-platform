
variable "spire_terraform_operator_token" {
  description = "Vault token lifetime for the host Terraform operator's SPIRE JWT auth role."
  type = object({
    ttl     = number
    max_ttl = number
  })
  default = {
    ttl     = 30 * 60
    max_ttl = 60 * 60
  }
}
