
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    bootstrapper = data.terraform_remote_state.vault_bootstrapper.outputs
    production   = data.terraform_remote_state.vault_production.outputs
  }
}

locals {
  production_vault_endpoint = "https://${local.state.production.service_vip}:${local.state.production.vault_api_port}"
  bootstrap_ca_chain_pem    = "${local.state.bootstrapper.bootstrap_root_ca_certificate_pem}\n${local.state.bootstrapper.bootstrap_intermediate_ca_certificate_pem}"
  pki_lease_ttl_seconds     = 60 * 60 * 24 * 365
}

locals {
  pki_roles = {
    for key, item in data.terraform_remote_state.foundation.outputs.global_pki_map : key => {
      name            = item.role_name
      auth_method     = item.auth_config.method
      auth_path       = item.auth_config.path
      approle_path    = item.auth_config.approle_path
      allowed_domains = item.dns_san
      ou              = item.ou
      max_ttl         = 60 * 60 * 24 * 90
      ttl             = 60 * 60 * 24 * 30
    }
  }
}
