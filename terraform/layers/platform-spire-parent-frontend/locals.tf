
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  # Extracts the SPIRE trust domain ("<stage>.<domain_suffix>") from module.context.svc_fqdn.
  # Asserts structural alignment with "<service_name>.<stage>.<domain_suffix>".
  # Pattern mismatches MUST trigger plan-time evaluation failure to prevent invalid trust domain propagation.
  spire_trust_domain   = regex("^[^.]+\\.(${module.context.svc_identity.stage}\\..+)$", module.context.svc_fqdn)[0]
  spire_server_port    = module.context.primary_net_config.lb_config.ports.api.frontend_port
  spire_oidc_port      = module.context.primary_net_config.lb_config.ports.oidc.frontend_port
  spire_parent_node_ip = one(module.context.svc_network.node_ips)

  # Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item C.
  bastion_pki_chain_pem = "${data.terraform_remote_state.vault_bastion.outputs.bastion_pki_root_cert_pem}\n${data.terraform_remote_state.vault_bastion.outputs.bastion_pki_inter_cert_pem}"

  oidc_listener_bundle = {
    server_cert_b64 = base64encode(vault_pki_secret_backend_cert.oidc_discovery.certificate)
    server_key_b64  = base64encode(vault_pki_secret_backend_cert.oidc_discovery.private_key)
    ca_cert_b64     = base64encode(local.bastion_pki_chain_pem)
  }

  ansible_template_config = {
    global_mss                 = module.context.global_mss
    spire_parent_vip           = module.context.primary_net_config.lb_config.vip
    spire_parent_cluster_name  = module.context.svc_identity.cluster_name
    spire_parent_node_ip       = local.spire_parent_node_ip
    spire_parent_static_routes = one(values(module.context.asymmetric_static_routes))
    spire_trust_domain         = local.spire_trust_domain
    spire_server_port          = local.spire_server_port
    spire_oidc_discovery_port  = local.spire_oidc_port

    # Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 4 Item B.
    spire_oidc_domain = local.spire_parent_node_ip
  }

  ansible_extra_config = {
    ansible_user = module.context.sec_vm_credentials.username

    spire_vault_upstream_addr               = data.terraform_remote_state.vault_bastion.outputs.bastion_vault_endpoint
    spire_vault_upstream_pki_mount_path     = data.terraform_remote_state.vault_bastion.outputs.bastion_pki_inter_mount_path
    spire_vault_upstream_approle_mount_path = data.terraform_remote_state.vault_bastion.outputs.approle_path
    spire_vault_upstream_role_id            = data.terraform_remote_state.vault_bastion.outputs.spire_upstream_authority.role_id
    spire_vault_upstream_secret_id          = data.terraform_remote_state.vault_bastion.outputs.spire_upstream_authority.secret_id
    spire_vault_upstream_ca_cert_b64        = filebase64(data.terraform_remote_state.vault_bastion.outputs.bastion_vault_listener_ca_cert_path)
  }
}
