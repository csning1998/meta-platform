
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    platform_vault_downstream_frontend = data.terraform_remote_state.platform_vault_downstream_frontend.outputs
    foundation_libvirt_resources       = data.terraform_remote_state.foundation_libvirt_resources.outputs
  }
}

# The platform layer publishes the runtime, and a runtime object stays null on the other runtime.
locals {
  project_code     = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
  runtime          = local.state.platform_vault_downstream_frontend.runtime
  is_runtime_talos = local.runtime.kubernetes_native
  vault_endpoint   = local.state.platform_vault_downstream_frontend.vault_endpoint
  kv_paths         = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["vault-downstream"]["frontend"]
}
