
variable "oidc_users" {
  description = "Map of users to create in Keycloak with their associated groups"
  type = map(object({
    username   = string
    email      = string
    first_name = string
    last_name  = string
    password   = string
    groups     = list(string)
  }))
  default = {}
}

variable "talos_workload_config" {
  description = "Keycloak workload of the Talos runtime. The images match the VM runtime, and the nodes pull them through the Harbor Origin mirrors. The local-path chart comes from its upstream OCI repository, as on the Downstream Vault."
  type = object({
    keycloak_image                          = optional(string, "quay.io/keycloak/keycloak:26.6.1")
    postgres_image                          = optional(string, "docker.io/library/postgres:18-alpine")
    database_storage_size                   = optional(string, "10Gi")
    local_path_provisioner_chart_repository = optional(string, "oci://ghcr.io/rancher/local-path-provisioner/charts")
    local_path_provisioner_chart_version    = optional(string, "0.0.37")
  })
  default = {}
}

variable "client_role_grants" {
  description = "Roles of each OIDC client, keyed by the client key of the layer, with the organization groups which receive each role. The service of a client reads the roles claim and maps each role name to its own permission."
  type        = map(map(list(string)))
  default     = {}
}

variable "keycloak_groups" {
  description = "Hierarchical group definitions with parents and attributes."
  type = map(object({
    parent      = optional(string, null)
    attributes  = optional(map(string), {})
    description = optional(string, "")
  }))
  default = {}
}
