
variable "realm_id" {
  description = "Keycloak realm ID that owns the provisioned OIDC clients."
  type        = string
}

variable "oidc_clients" {
  description = "OIDC clients to provision, keyed by service name."
  type = map(object({
    client_id           = string
    name                = string
    valid_redirect_uris = list(string)
    web_origin          = string
  }))
}

variable "vault_kv_mount" {
  description = "Vault KV v2 mount path storing the generated client secrets."
  type        = string
  default     = "secret"
}

variable "vault_kv_namespace" {
  description = "Vault KV namespace prefix under which client secrets are stored."
  type        = string
}

variable "issuer_url" {
  description = "OIDC issuer URL, stored alongside each client secret for downstream discovery."
  type        = string
}
