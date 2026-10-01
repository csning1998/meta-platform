
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  state = {
    foundation_libvirt_resources      = data.terraform_remote_state.foundation_libvirt_resources.outputs
    foundation_vault_bastion          = data.terraform_remote_state.foundation_vault_bastion.outputs
    platform_spire_parent             = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_parent            = data.terraform_remote_state.provision_spire_parent.outputs
    security_vault_downstream_pki     = data.terraform_remote_state.security_vault_downstream_pki.outputs
    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    provision_spire_child             = data.terraform_remote_state.provision_spire_child.outputs
  }
}

locals {
  project_code       = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
  cluster_name       = local.state.foundation_libvirt_resources.foundation_topology.identity["harbor-origin"]["frontend"].cluster_name
  terraform_operator = local.state.provision_spire_parent.terraform_operator["harbor-origin"]

  tenant_login = local.state.security_vault_downstream_tenants.downstream_tenants.tenant_login[module.context.svc_identity.cluster_name]

  sec_vault_agent_identity = merge(module.context.vault_agent_identity_base, {
    auth_path      = local.tenant_login.auth_mount
    auth_role_name = local.tenant_login.role_name
  })
}

# Requires inclusion of the catalog service VIP within the certificate IP SAN to support the HAProxy-fronted VIP.
locals {
  # Bootstrap listener endpoints MUST bind to the lowest numerical IP address
  # to guarantee deterministic configuration across non-ordered map iterations.
  harbor_listen_ip = sort(local.harbor_node_ips)[0]
  harbor_node_ips = flatten([
    for comp_name, comp_config in var.service_config : [
      for node_suffix, node_data in comp_config.nodes :
      cidrhost(module.context.primary_net_config.network.hostonly.cidr, node_data.ip_suffix)
    ]
  ])

  downstream_pki_listener_bundle = {
    server_cert_b64 = base64encode(vault_pki_secret_backend_cert.listener.certificate)
    server_key_b64  = base64encode(vault_pki_secret_backend_cert.listener.private_key)
    ca_cert_b64     = module.context.vault_agent_identity_base.ca_cert_b64
  }

  spire_workload_spiffe_id = "spiffe://${local.state.platform_spire_parent.spire_agent_bootstrap.trust_domain}/${local.state.foundation_libvirt_resources.foundation_vault_path.project_code}/${module.context.primary_context.s_name}/${module.context.primary_context.c_name}"
}

locals {
  ansible_template_vars = {
    global_mss                     = module.context.global_mss
    access_scope                   = module.context.primary_net_config.network.hostonly.cidr
    service_name                   = module.context.primary_context.s_name
    service_identifier             = module.context.primary_context.s_name
    harbor_origin_fqdn             = module.context.svc_fqdn
    harbor_origin_service_domain   = module.context.svc_identity.cluster_name
    harbor_origin_mtls_node_subnet = module.context.primary_net_config.network.hostonly.cidr
    harbor_origin_vip              = module.context.primary_net_config.lb_config.vip
    harbor_origin_tls_port         = module.context.primary_net_config.lb_config.ports["https"].frontend_port
    harbor_origin_metrics_port     = module.context.primary_net_config.lb_config.ports["metrics"].frontend_port
    harbor_origin_listen_address   = local.harbor_listen_ip
    harbor_origin_cluster_ips      = local.harbor_node_ips
  }

  harbor_origin_secrets = data.vault_kv_secret_v2.harbor_origin.data

  ansible_extra_vars = {
    harbor_origin_admin_password = sensitive(local.harbor_origin_secrets["harbor_origin_admin_password"])
    harbor_origin_pg_db_password = sensitive(local.harbor_origin_secrets["harbor_origin_pg_db_password"])

    spire_server_port               = tostring(local.state.platform_spire_parent.spire_agent_bootstrap.server_port)
    spire_parent_node_ip            = local.state.platform_spire_parent.spire_agent_bootstrap.node_ip
    spire_parent_ssh_host           = local.state.platform_spire_parent.spire_agent_bootstrap.ssh_host
    spire_trust_domain              = local.state.platform_spire_parent.spire_agent_bootstrap.trust_domain
    spire_workload_spiffe_id        = local.spire_workload_spiffe_id
    spire_cluster_name              = module.context.svc_identity.cluster_name
    spire_parent_join_token_kv_path = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["spire"]["parent"].join_token
    spire_child_join_token_kv_path  = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["spire"]["child"].join_token
    spire_child_agent_address       = local.state.provision_spire_child.spire_child_agent_endpoint.address
    spire_child_agent_port          = tostring(local.state.provision_spire_child.spire_child_agent_endpoint.port)
    spire_child_kubeconfig_kv_path  = local.state.provision_spire_child.spire_child_registrar_kv_path
    vault_agent_jwt_audience        = local.tenant_login.audience

    bastion_vault_ca_cert_path  = local.state.foundation_vault_bastion.bastion_vault.listener_ca_cert_path
    bastion_operator_wrapper    = local.terraform_operator.wrapper_name
    bastion_operator_role       = local.terraform_operator.role_name
    bastion_operator_auth_mount = local.state.platform_spire_parent.spire_oidc_auth_backend_path
  }
}
