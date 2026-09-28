
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  owner_code = "meta-platform"

  bastion_pki_chain_pem = "${data.terraform_remote_state.vault_bastion.outputs.bastion_vault_pki.root_cert_pem}\n${data.terraform_remote_state.vault_bastion.outputs.bastion_vault_pki.intermediate_cert_pem}"

  ansible_template_config = {
    global_mss         = module.context.global_mss
    vault_vip          = module.context.primary_net_config.lb_config.vip
    vault_cluster_name = module.context.svc_identity.cluster_name
  }

  ansible_extra_config = {
    ansible_user          = module.context.sec_vm_credentials.username
    dev_vault_url         = var.bastion_vault_endpoint
    dev_vault_api_path    = "meta-platform/credentials"
    vault_server_cert_b64 = base64encode(vault_pki_secret_backend_cert.vault_listener.certificate)
    vault_server_key_b64  = base64encode(vault_pki_secret_backend_cert.vault_listener.private_key)
    vault_ca_cert_b64     = base64encode(local.bastion_pki_chain_pem)
  }
}
