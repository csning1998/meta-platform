
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
  }
}

# Provider prerequisites: Must be defined as root-level locals because provider blocks cannot reference module outputs.
locals {
  project_code = local.state.security_vault_downstream_tenants.foundation_vault_path.project_code
  kv_paths     = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths

  # The addon prefix completes as addon-<name>, the form which platform-cilium-hubble grants to External Secrets Operator.
  kv_path_cilium_hubble_ui = "${local.kv_paths["cilium"]["hubble"].addon}-hubble-ui"

  downstream_vault = {
    endpoint     = local.state.security_vault_downstream_tenants.endpoint
    ca_cert_path = local.state.security_vault_downstream_tenants.ca_cert_path
  }
}
