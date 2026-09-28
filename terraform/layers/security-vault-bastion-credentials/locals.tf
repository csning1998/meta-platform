
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  owner_code = "meta-platform"

  state = {
    vault_bastion = data.terraform_remote_state.vault_bastion.outputs
    foundation    = data.terraform_remote_state.foundation.outputs
  }
}

# Per-service extra generated secrets, layered on top of the SSH identity every
# service_identity entry already carries.
locals {
  service_generates = {
    "platform-haproxy-frontend" = {
      keepalived_auth_pass = { length = 32 }
    }
  }
}
