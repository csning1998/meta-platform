
output "keycloak_issuer_url" {
  description = "Keycloak OIDC realm issuer URL."
  value       = "${local.keycloak_frontend_url}/realms/${local.keycloak_realm_id}"
}

output "keycloak_gitlab_sync_root_org" {
  description = "The root organization name targeted for GitLab synchronization."
  value = one([
    for k, v in var.keycloak_groups : k
    if v.parent == null && lookup(v.attributes, "sync_to_gitlab", "false") == "true"
  ])
}

output "keycloak_root_groups_metadata" {
  description = "Metadata for top-level organizational groups."
  value = {
    for k, v in var.keycloak_groups : k => {
      name        = k
      description = v.description
      attributes  = v.attributes
    } if v.parent == null
  }
}

output "keycloak_groups_metadata" {
  description = "Sanitized metadata for all groups."
  value = {
    for k, v in var.keycloak_groups : k => {
      description = v.description
      parent      = v.parent
      attributes  = v.attributes
    }
  }
}

output "keycloak_oidc_clients" {
  description = "Map of created Keycloak OpenID clients."
  value       = keycloak_openid_client.clients
  sensitive   = true
}

output "keycloak_vault_redirect_uris" {
  description = "Allowed Vault OIDC callback redirect URIs."
  value       = local.vault_redirect_uris
}

output "keycloak_groups" {
  description = "Full configuration map of Keycloak groups."
  value       = var.keycloak_groups
}

output "keycloak_node_exporter_targets" {
  description = "Node Exporter scrape target for the Keycloak node."
  value       = local.state.platform_keycloak_frontend.generic_cluster.node_exporter_targets
}

# Since GitLab CE does not support native OIDC inventory/sync,
# this user data must be passed via remote states to enable shadow account provisioning in platform-gitlab-governance.
output "keycloak_oidc_users" {
  description = "User inventory for downstream layers. Marked as sensitive because it contains initial passwords."
  value = {
    for k, v in var.oidc_users : k => {
      id         = keycloak_user.users[k].id
      username   = v.username
      first_name = v.first_name
      last_name  = v.last_name
      email      = v.email
      groups     = v.groups
      password   = v.password
    }
  }
  sensitive = true
}
