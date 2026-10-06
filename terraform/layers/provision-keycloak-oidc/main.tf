
# On the Talos runtime the realm waits for the Keycloak rollout of runtime-talos.tf, and the module is absent on the VM runtime.
resource "keycloak_realm" "infra_realm" {
  depends_on = [module.manifest_keycloak]

  realm             = local.realm_id
  enabled           = true
  display_name      = "Infrastructure Centralized Identity"
  display_name_html = "<b>Infrastructure Centralized Identity</b>"

  login_with_email_allowed = true
  reset_password_allowed   = true
  remember_me              = true

  internationalization {
    supported_locales = ["en", "zh-CN"]
    default_locale    = "en"
  }
}

locals {
  # Keeps vault_frontend static because the client carries the audience mapper and multiple redirect URIs, unlike single-callback services.
  oidc_clients_all = merge({
    vault_frontend = {
      client_id           = "vault-infra"
      name                = "Vault Infrastructure"
      valid_redirect_uris = local.vault_redirect_uris
      web_origin          = local.vault_frontend_url
    }
  }, local.downstream_oidc_clients_resolved)
}


# Injects the target audience claim required by Vault OIDC backend token verification.
resource "keycloak_openid_audience_protocol_mapper" "vault_audience" {
  realm_id  = keycloak_realm.infra_realm.id
  client_id = keycloak_openid_client.clients["vault_frontend"].id
  name      = "audience-mapper"

  included_custom_audience = "vault-infra"
  add_to_id_token          = true
  add_to_access_token      = true
}

resource "keycloak_group" "root_groups" {
  for_each = { for k, v in var.keycloak_groups : k => v if v.parent == null }
  realm_id = keycloak_realm.infra_realm.id
  name     = each.key

  attributes = each.value.attributes

  lifecycle {
    prevent_destroy = true
  }
}

resource "keycloak_group" "subgroups" {
  for_each  = { for k, v in var.keycloak_groups : k => v if v.parent != null }
  realm_id  = keycloak_realm.infra_realm.id
  name      = each.key
  parent_id = keycloak_group.root_groups[each.value.parent].id

  attributes = each.value.attributes

  lifecycle {
    prevent_destroy = true
  }
}

resource "keycloak_user" "users" {
  for_each       = var.oidc_users
  realm_id       = keycloak_realm.infra_realm.id
  username       = each.value.username
  enabled        = true
  email          = each.value.email
  first_name     = each.value.first_name
  last_name      = each.value.last_name
  email_verified = true

  initial_password {
    value     = each.value.password
    temporary = false
  }
}


resource "keycloak_user_groups" "user_assignments" {
  for_each = var.oidc_users
  realm_id = keycloak_realm.infra_realm.id
  user_id  = keycloak_user.users[each.key].id

  group_ids = [
    for g in each.value.groups : local.all_group_ids[g]
  ]
}
