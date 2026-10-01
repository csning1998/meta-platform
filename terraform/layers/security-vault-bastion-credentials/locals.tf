
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  state = {
    foundation_vault_bastion     = data.terraform_remote_state.foundation_vault_bastion.outputs
    foundation_libvirt_resources = data.terraform_remote_state.foundation_libvirt_resources.outputs
  }
  project_code = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
}

# The SSH identity leaf of every SSH-enabled cluster, keyed by cluster_name like the key files.
locals {
  ssh_paths = {
    for key, path in local.state.foundation_libvirt_resources.foundation_vault_path.ssh_credential_paths : key => path
    if contains(keys(local.state.foundation_libvirt_resources.foundation_ssh.identity_key_paths), key)
  }
}

# The addon prefix of foundation-libvirt-resources completes as addon-<name>, the form which platform-cilium-frontend grants to ESO.
locals {
  kv_path = {
    haproxy_app      = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["haproxy"]["frontend"].app
    cilium_hubble_ui = "${local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["cilium"]["frontend"].addon}-hubble-ui"
  }
}
