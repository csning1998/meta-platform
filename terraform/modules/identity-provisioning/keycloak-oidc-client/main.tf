
resource "random_password" "client_secrets" {
  for_each = var.oidc_clients
  length   = 32
  special  = false
}

resource "keycloak_openid_client" "clients" {
  for_each = var.oidc_clients

  realm_id              = var.realm_id
  client_id             = each.value.client_id
  name                  = each.value.name
  enabled               = true
  access_type           = "CONFIDENTIAL"
  client_secret         = random_password.client_secrets[each.key].result
  standard_flow_enabled = true
  valid_redirect_uris   = each.value.valid_redirect_uris
  web_origins           = [each.value.web_origin]
}

resource "keycloak_openid_group_membership_protocol_mapper" "group_mapper" {
  for_each            = keycloak_openid_client.clients
  realm_id            = var.realm_id
  client_id           = each.value.id
  name                = "group-mapper"
  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
}

resource "vault_kv_secret_v2" "oidc_clients" {
  provider = vault
  for_each = var.oidc_clients
  mount    = var.vault_kv_mount
  name     = "${var.vault_kv_namespace}/keycloak/oidc/clients/${each.key}"

  data_json = jsonencode({
    client_id     = each.value.client_id
    client_secret = random_password.client_secrets[each.key].result
    issuer        = var.issuer_url
  })
}
