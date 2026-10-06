
variable "cluster_name" {
  description = "Name of the Kubernetes cluster. The auth mount, the roles, and the policies derive their names from the cluster name."
  type        = string
}

variable "kubernetes_identity_config" {
  description = "Kubernetes identities which authenticate to Vault: the ClusterIssuer of cert-manager with its token ServiceAccount, and the ServiceAccount of External Secrets Operator."
  type = object({
    cluster_issuer_name              = optional(string, "platform-cluster-issuer")
    cert_manager_namespace           = optional(string, "cert-manager")
    cluster_issuer_service_account   = optional(string, "platform-cluster-issuer")
    external_secrets_namespace       = optional(string, "external-secrets")
    external_secrets_service_account = optional(string, "external-secrets-vault")
  })
  default = {}
}

variable "pki_config" {
  description = "PKI engine against which the ClusterIssuer signs. A role_name names a role which another layer owns. A null role_name makes this module own a role named after the cluster, which signs P-256 keys alone and is built from role_allowed_domains, role_allow_ip_sans, and role_ou. An issuer_policy_name names an existing policy which grants the sign path, such as the assignable policy which parent-group-governance declares on the Bastion Vault or the workload policy which security-vault-downstream-tenants declares on the Downstream Vault. A null issuer_policy_name makes this module write the policy."
  type = object({
    mount_path           = string
    role_name            = optional(string)
    issuer_policy_name   = optional(string)
    role_allowed_domains = optional(list(string), [])
    role_allow_ip_sans   = optional(bool, false)
    role_ou              = optional(list(string), [])
  })

  validation {
    condition     = var.pki_config.role_name != null || length(var.pki_config.role_allowed_domains) > 0
    error_message = "A PKI role owned by this module requires at least one allowed domain."
  }
}

variable "external_secrets_config" {
  description = "KV v2 mount and paths which External Secrets Operator reads. A policy_name names an existing policy which grants the paths, such as a workload policy which security-vault-downstream-tenants declares, and a null policy_name makes this module write the policy. Null omits the role and the policy of External Secrets Operator, for a cluster without the operator."
  type = object({
    kv_mount_path = optional(string, "secret")
    kv_paths      = list(string)
    policy_name   = optional(string)
  })
  default = null
}
