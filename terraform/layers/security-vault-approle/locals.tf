
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
  prod_vault_endpoint        = "https://${local.state.production.service_vip}:${local.state.production.prod_vault_api_port}"
  prod_pki_issuer_mount_path = data.terraform_remote_state.foundation.outputs.global_pki_config.mount_path
}
