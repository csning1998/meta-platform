
# 1. Realm Configuration
resource "keycloak_realm" "infra_realm" {
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
  # vault_frontend is kept as a static entry: it carries the OIDC audience mapper and
  # multiple UI/CLI redirect URIs, unlike the single-callback downstream services.
  oidc_clients_all = merge({
    vault_frontend = {
      client_id           = "vault-infra"
      name                = "Vault Infrastructure"
      valid_redirect_uris = local.vault_redirect_uris
      web_origin          = local.vault_frontend_url
    }
  }, local.downstream_oidc_clients_resolved)
}

# 2. OIDC Clients, Secret Generation, and Vault KV Storage
module "oidc_clients" {
  source = "../../modules/identity-provisioning/keycloak-oidc-client"
  providers = {
    keycloak = keycloak
    vault    = vault.production
  }

  realm_id           = keycloak_realm.infra_realm.id
  oidc_clients       = local.oidc_clients_all
  vault_kv_namespace = data.terraform_remote_state.security_vault_approle.outputs.vault_kv_namespace
  issuer_url         = "${local.keycloak_frontend_url}/realms/${local.realm_id}"
}

# Audience Mapper for Vault to verify Token
resource "keycloak_openid_audience_protocol_mapper" "vault_audience" {
  realm_id  = keycloak_realm.infra_realm.id
  client_id = module.oidc_clients.clients["vault_frontend"].id
  name      = "audience-mapper"

  included_custom_audience = "vault-infra"
  add_to_id_token          = true
  add_to_access_token      = true
}

# 6. Test User & Groups Configuration
# 6a. Root Level Groups (Parents)
resource "keycloak_group" "root_groups" {
  for_each = { for k, v in var.keycloak_groups : k => v if v.parent == null }
  realm_id = keycloak_realm.infra_realm.id
  name     = each.key

  attributes = each.value.attributes

  lifecycle {
    prevent_destroy = true
  }
}

# 6b. Subgroups (Children)
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

locals {
  # Helper to merge both group layers for easy lookup
  all_group_ids = merge(
    { for k, v in keycloak_group.root_groups : k => v.id },
    { for k, v in keycloak_group.subgroups : k => v.id }
  )
}

resource "keycloak_user_groups" "user_assignments" {
  for_each = var.oidc_users
  realm_id = keycloak_realm.infra_realm.id
  user_id  = keycloak_user.users[each.key].id

  group_ids = [
    for g in each.value.groups : local.all_group_ids[g]
  ]
}
