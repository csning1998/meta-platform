
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    security_vault_downstream_pki     = data.terraform_remote_state.security_vault_downstream_pki.outputs
    platform_harbor_origin_frontend   = data.terraform_remote_state.platform_harbor_origin_frontend.outputs
  }

  sys_vault_endpoint = "https://${local.state.security_vault_downstream_tenants.service_vip}:443"
  kv_paths           = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths
}

# The client identifier comes from the service catalog, and the issuer follows the realm which provision-keycloak-oidc declares.
locals {
  keycloak_realm = "infra-company"
  oidc_client_id = local.state.security_vault_downstream_tenants.foundation_pki.map["harbor-origin-frontend"].oidc_client.client_id
  oidc_issuer    = "https://${local.state.security_vault_downstream_tenants.foundation_pki.map["keycloak-frontend"].dns_san[0]}/realms/${local.keycloak_realm}"
}

# The operator of this component logs in to the Downstream Vault with the JWT-SVID of the SPIRE Parent.
locals {
  downstream_operator = local.state.security_vault_downstream_tenants.component_operators["harbor-origin"]
}
