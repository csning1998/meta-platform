
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  state = {
    foundation_libvirt_resources = data.terraform_remote_state.foundation_libvirt_resources.outputs
    foundation_vault_bastion     = data.terraform_remote_state.foundation_vault_bastion.outputs
    platform_cilium_frontend     = data.terraform_remote_state.platform_cilium_frontend.outputs
    platform_spire_parent        = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_parent       = data.terraform_remote_state.provision_spire_parent.outputs
  }

  terraform_operator    = local.state.provision_spire_parent.terraform_operator["vault-downstream"]
  bastion_pki_chain_pem = "${local.state.foundation_vault_bastion.bastion_vault_pki.root_cert_pem}\n${local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_cert_pem}"
}

locals {
  project_code = local.state.foundation_libvirt_resources.foundation_vault_path.project_code

  ansible_template_config = {
    global_mss         = module.context.global_mss
    vault_vip          = module.context.primary_net_config.lb_config.vip
    vault_cluster_name = module.context.svc_identity.cluster_name
  }

  # Variables required exclusively by platform_vault unseal tasks (tasks/D-unseal.yaml).
  # Exported to local_file.unseal_vars for platform CLI post-reboot unseal operations without a Terraform run.
  ansible_unseal_vars = {
    bastion_vault_url                  = var.bastion_vault_endpoint
    bastion_vault_ca_cert_path         = local.state.foundation_vault_bastion.bastion_vault.listener_ca_cert_path
    platform_vault_init_kv_path        = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["vault-downstream"]["frontend"].init
    platform_vault_operator_wrapper    = local.terraform_operator.wrapper_name
    platform_vault_operator_role       = local.terraform_operator.role_name
    platform_vault_operator_auth_mount = local.state.platform_spire_parent.spire_oidc_auth_backend_path
  }

  ansible_extra_config = merge(local.ansible_unseal_vars, {
    ansible_user          = module.context.sec_vm_credentials.username
    vault_server_cert_b64 = base64encode(vault_pki_secret_backend_cert.vault_listener.certificate)
    vault_server_key_b64  = base64encode(vault_pki_secret_backend_cert.vault_listener.private_key)
    vault_ca_cert_b64     = base64encode(local.bastion_pki_chain_pem)
  })
}
