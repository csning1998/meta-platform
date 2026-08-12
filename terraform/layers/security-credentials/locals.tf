
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

# Provider prerequisites: Must be defined as root-level locals because provider blocks cannot reference module outputs.
locals {
  sys_vault_endpoint  = "https://${data.terraform_remote_state.security_vault_approle.outputs.prod_vault_svc_vip}:443"
  vault_pki_cert_path = data.terraform_remote_state.security_pki.outputs.bastion_pki_chain_b64.path
  vault_kv_namespace  = data.terraform_remote_state.security_vault_approle.outputs.vault_kv_namespace
}
