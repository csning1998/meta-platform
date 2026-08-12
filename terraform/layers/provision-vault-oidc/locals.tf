
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    vault_sys            = data.terraform_remote_state.vault_sys.outputs
    vault_pki            = data.terraform_remote_state.vault_pki.outputs
    vault_prod_bootstrap = data.terraform_remote_state.vault_prod_bootstrap.outputs
    keycloak_oidc        = data.terraform_remote_state.keycloak_provisioning.outputs
  }

  vault_endpoint = "https://${local.state.vault_sys.service_vip}:443"
  vault_fqdn     = "https://${local.state.vault_prod_bootstrap.global_pki_map["vault-frontend"].dns_san[0]}"

  # OIDC Configuration
  oidc_discovery_url = local.state.keycloak_oidc.issuer_url
  oidc_client_id     = data.vault_kv_secret_v2.keycloak_vault_client.data["client_id"]
  oidc_client_secret = data.vault_kv_secret_v2.keycloak_vault_client.data["client_secret"]
}
