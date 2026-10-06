
# Every OIDC client gets a generated secret, a group membership mapper, and a Downstream KV entry for its consumer.
resource "random_password" "client_secrets" {
  for_each = local.oidc_clients_all
  length   = 32
  special  = false
}

resource "keycloak_openid_client" "clients" {
  for_each = local.oidc_clients_all

  realm_id              = keycloak_realm.infra_realm.id
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
  realm_id            = keycloak_realm.infra_realm.id
  client_id           = each.value.id
  name                = "group-mapper"
  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
}

resource "vault_kv_secret_v2" "oidc_clients" {
  provider = vault.downstream
  for_each = local.oidc_clients_all
  mount    = "secret"
  name     = "${local.state.security_vault_downstream_tenants.foundation_vault_path.project_code}/keycloak/oidc/clients/${each.key}"

  data_json = jsonencode({
    client_id     = each.value.client_id
    client_secret = random_password.client_secrets[each.key].result
    issuer        = "${local.keycloak_frontend_url}/realms/${local.keycloak_realm_id}"
  })
}
