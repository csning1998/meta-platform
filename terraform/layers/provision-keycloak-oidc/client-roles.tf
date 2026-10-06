# Each OIDC client owns its roles, and organization groups only receive grants of those roles. A reorganization
# changes the grant table alone, and the token of a client carries the roles of that client and of no other client.
locals {
  client_roles = merge([
    for client_key, roles in var.client_role_grants : {
      for role, groups in roles : "${client_key}/${role}" => { client_key = client_key, role = role, groups = groups }
    }
  ]...)

  group_role_grants = {
    for group in distinct(flatten([for grant in values(local.client_roles) : grant.groups])) : group => [
      for key, grant in local.client_roles : keycloak_role.client_roles[key].id if contains(grant.groups, group)
    ]
  }
}

resource "keycloak_role" "client_roles" {
  for_each = local.client_roles

  realm_id  = keycloak_realm.infra_realm.id
  client_id = keycloak_openid_client.clients[each.value.client_key].id
  name      = each.value.role
}

resource "keycloak_group_roles" "grants" {
  for_each = local.group_role_grants

  realm_id = keycloak_realm.infra_realm.id
  group_id = local.all_group_ids[each.key]
  role_ids = each.value
}

# The roles claim lists the roles of the client which requests the token, without a client prefix.
resource "keycloak_openid_user_client_role_protocol_mapper" "roles" {
  for_each = { for key in keys(var.client_role_grants) : key => keycloak_openid_client.clients[key] }

  realm_id                    = keycloak_realm.infra_realm.id
  client_id                   = each.value.id
  name                        = "client-roles"
  claim_name                  = "roles"
  client_id_for_role_mappings = each.value.client_id
  multivalued                 = true
  add_to_id_token             = true
  add_to_access_token         = true
  add_to_userinfo             = true
}
