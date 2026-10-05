
variable "keycloak_config" {
  description = "Keycloak server. The hostname is the public FQDN which the issued tokens carry. The TLS Secret holds tls.crt and tls.key, and Keycloak serves HTTPS on https_port and the management interface on management_port."
  type = object({
    namespace       = string
    image           = string
    hostname        = string
    tls_secret_name = string
    https_port      = optional(number, 8443)
    management_port = optional(number, 9000)
    resources = optional(object({
      requests = map(string)
      limits   = map(string)
      }), {
      requests = { cpu = "250m", memory = "768Mi" }
      limits   = { memory = "1536Mi" }
    })
  })
}

variable "database_config" {
  description = "In-cluster PostgreSQL which holds the Keycloak database. The volume claim binds to storage_class_name."
  type = object({
    image              = string
    storage_class_name = string
    storage_size       = string
  })
}

variable "credential_secret" {
  description = "Secret in the Keycloak namespace which holds the bootstrap administrator and the database credentials, with the key name of each field."
  type = object({
    name               = string
    admin_user_key     = string
    admin_password_key = string
    db_user_key        = string
    db_password_key    = string
  })
}

variable "service_config" {
  description = "Service which publishes Keycloak on an address which a node already holds, for example the Talos control plane VIP. Cilium kube-proxy replacement serves the externalIPs of a Service."
  type = object({
    external_ip = string
    port        = optional(number, 443)
  })
}
