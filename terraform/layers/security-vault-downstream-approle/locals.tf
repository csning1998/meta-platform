
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  owner_code = "meta-platform"

  state = {
    vault_bastion    = data.terraform_remote_state.vault_bastion.outputs
    vault_downstream = data.terraform_remote_state.vault_downstream.outputs
  }
}

locals {
  prod_vault_endpoint        = "https://${local.state.vault_downstream.service_vip}:${local.state.vault_downstream.prod_vault_api_port}"
  prod_pki_issuer_mount_path = data.terraform_remote_state.foundation.outputs.global_pki_config.mount_path
}
