
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    platform_vault_downstream_frontend = data.terraform_remote_state.platform_vault_downstream_frontend.outputs
    security_vault_downstream_tenants  = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    security_vault_downstream_pki      = data.terraform_remote_state.security_vault_downstream_pki.outputs
    provision_keycloak_oidc            = data.terraform_remote_state.provision_keycloak_oidc.outputs
  }
}

locals {
  downstream_vault = {
    endpoint = local.state.platform_vault_downstream_frontend.vault_endpoint.address
    fqdn     = "https://${local.state.security_vault_downstream_tenants.foundation_pki.map["vault-downstream-frontend"].dns_san[0]}"
  }

  # OIDC Configuration
  oidc_discovery_url = local.state.provision_keycloak_oidc.keycloak_issuer_url
  oidc_client_id     = data.vault_kv_secret_v2.keycloak_vault_client.data["client_id"]
  oidc_client_secret = data.vault_kv_secret_v2.keycloak_vault_client.data["client_secret"]
}

# The operator of this component logs in to the Downstream Vault with the JWT-SVID of the SPIRE Parent.
locals {
  terraform_operator_subject = { service = "vault-downstream", component = "frontend" }
  terraform_operator         = local.state.security_vault_downstream_tenants.downstream_vault_operators[local.terraform_operator_subject.service][local.terraform_operator_subject.component]
}
