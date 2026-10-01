
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    security_vault_downstream_pki     = data.terraform_remote_state.security_vault_downstream_pki.outputs
    platform_keycloak_frontend        = data.terraform_remote_state.platform_keycloak_frontend.outputs
    provision_spire_child             = data.terraform_remote_state.provision_spire_child.outputs
  }
}

locals {
  fdqn = {
    keycloak_frontend = local.state.security_vault_downstream_tenants.foundation_pki.map["keycloak-frontend"].dns_san[0]
    vault_frontend    = local.state.security_vault_downstream_tenants.foundation_pki.map["vault-downstream-frontend"].dns_san[0]
  }
}

locals {
  all_groups = distinct(flatten([for u in var.oidc_users : u.groups]))
  all_group_ids = merge(
    { for k, v in keycloak_group.root_groups : k => v.id },
    { for k, v in keycloak_group.subgroups : k => v.id }
  )
}

locals {
  # Downstream OIDC clients derived from global_pki_map: declaring oidc_client on a
  # component in service_catalog is sufficient to onboard a new consumer here.
  downstream_oidc_clients_resolved = {
    for k, v in local.state.security_vault_downstream_tenants.foundation_pki.map : k => {
      client_id           = v.oidc_client.client_id
      name                = v.oidc_client.name
      valid_redirect_uris = ["https://${v.dns_san[0]}${v.oidc_client.redirect_path}"]
      web_origin          = "https://${v.dns_san[0]}"
    }
    if v.oidc_client != null
  }
}

locals {
  # Endpoint Construction
  keycloak_frontend_url = "https://${local.fdqn.keycloak_frontend}"
  vault_frontend_url    = "https://${local.fdqn.vault_frontend}"

  # Admin Credentials
  keycloak_admin_user     = ephemeral.vault_kv_secret_v2.keycloak_admin.data["keycloak_admin_user"]
  keycloak_admin_password = ephemeral.vault_kv_secret_v2.keycloak_admin.data["keycloak_admin_password"]

  # OIDC Configuration Constants
  realm_id = "infra-company"

  # Centralized Redirect URIs for Vault
  vault_redirect_uris = [
    "${local.vault_frontend_url}/ui/vault/auth/oidc/oidc/callback",
    "${local.vault_frontend_url}/ui/vault/auth/oidc/callback",
    "${local.vault_frontend_url}/vault/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]
}

locals {
  kv_paths = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths
}
