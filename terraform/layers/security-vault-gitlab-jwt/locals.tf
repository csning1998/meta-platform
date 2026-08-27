
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    vault_bastion = data.terraform_remote_state.vault_bastion.outputs
  }
}

locals {
  jwt_auth_backend_path = "gitlab-saas-jwt"
  kv_mount_path         = "secret"
}
