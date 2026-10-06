
# Kubernetes auth mount, roles, and policies by which in-cluster cert-manager and External Secrets Operator log in to Vault.
# 1. Auth Method Backend & Roles
locals {
  auth_mount_path            = "${var.cluster_name}-service-account-token-provider"
  auth_role_cluster_issuer   = var.cluster_name
  auth_role_external_secrets = "${var.cluster_name}-external-secrets"
}

# 2. Secrets Engine (PKI Action Endpoint & Role Resolution)
locals {
  pki_action_path = "sign"
  pki_role_name   = coalesce(var.pki_config.role_name, one(vault_pki_secret_backend_role.cluster_issuer[*].name))
}

# 3. Policy Store (Core ACL Named Rules)
locals {
  policy_name_cluster_issuer   = coalesce(var.pki_config.issuer_policy_name, one(vault_policy.cluster_issuer[*].name))
  policy_name_external_secrets = var.external_secrets_config == null ? null : coalesce(var.external_secrets_config.policy_name, one(vault_policy.external_secrets[*].name))
}

# 4. Identity Mapping
locals {
  identity = var.kubernetes_identity_config
}
