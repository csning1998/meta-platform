
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  state = {
    foundation_libvirt_resources      = data.terraform_remote_state.foundation_libvirt_resources.outputs
    platform_cilium_frontend          = data.terraform_remote_state.platform_cilium_frontend.outputs
    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    security_vault_downstream_pki     = data.terraform_remote_state.security_vault_downstream_pki.outputs
    foundation_vault_bastion          = data.terraform_remote_state.foundation_vault_bastion.outputs
    platform_spire_parent             = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_parent            = data.terraform_remote_state.provision_spire_parent.outputs
    provision_spire_child             = data.terraform_remote_state.provision_spire_child.outputs
  }
}

# Provider prerequisites: Must be defined as root-level locals because provider blocks cannot reference module outputs.
locals {
  sys_vault_endpoint  = "https://${local.state.security_vault_downstream_tenants.service_vip}:443"
  vault_pki_cert_path = local.state.security_vault_downstream_pki.bastion_pki_chain_b64.path
}

locals {
  kv_paths = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths
}

locals {
  # Configures VM Vault Agent workload authentication using SPIRE Child JWT-SVID credentials.
  tenant_login = local.state.security_vault_downstream_tenants.downstream_tenants.tenant_login[module.context.svc_identity.cluster_name]

  sec_vault_agent_identity = merge(module.context.vault_agent_identity_base, {
    auth_path      = local.tenant_login.auth_mount
    auth_role_name = local.tenant_login.role_name
  })

  terraform_operator       = local.state.provision_spire_parent.terraform_operator["keycloak"]
  spire_parent             = local.state.platform_spire_parent.spire_agent_bootstrap
  spire_workload_spiffe_id = "spiffe://${local.spire_parent.trust_domain}/${local.state.security_vault_downstream_tenants.foundation_vault_path.project_code}/${module.context.primary_context.s_name}/${module.context.primary_context.c_name}"
}

locals {
  ansible_template_vars = {
    service_identifier      = module.context.primary_context.s_name
    keycloak_fqdn           = module.context.svc_fqdn
    keycloak_service_domain = module.context.svc_identity.cluster_name
    keycloak_vip            = module.context.primary_net_config.lb_config.vip
    keycloak_port           = module.context.primary_net_config.lb_config.ports["https"].frontend_port
    keycloak_node_subnet    = module.context.primary_net_config.network.hostonly.cidr
    vault_vip               = module.context.prod_vault_svc_vip
    global_mss              = module.context.global_mss

    infra_keycloak_cluster_ips = [
      for comp_name, comp_config in var.service_config : [
        for node_suffix, node_data in comp_config.nodes :
        cidrhost(module.context.primary_net_config.network.hostonly.cidr, node_data.ip_suffix)
      ]
    ][0]

    access_scope = module.context.primary_net_config.network.hostonly.cidr
    service_name = module.context.primary_context.s_name
  }

  # Vault access configuration for Ansible operator login and secret retrieval.
  vault_access = {
    bastion = {
      endpoint     = local.state.foundation_vault_bastion.bastion_vault.endpoint
      ca_cert_path = local.state.foundation_vault_bastion.bastion_vault.listener_ca_cert_path
      auth_mount   = local.state.platform_spire_parent.spire_oidc_auth_backend_path
      role         = local.terraform_operator.role_name
      wrapper      = local.terraform_operator.wrapper_name
    }
    downstream = {
      endpoint     = local.state.security_vault_downstream_tenants.endpoint
      ca_cert_path = local.state.security_vault_downstream_tenants.ca_cert_path
      auth_mount   = local.state.security_vault_downstream_tenants.tenant_operator.auth_mount
      role         = local.state.security_vault_downstream_tenants.tenant_operator.role_name
      wrapper      = local.state.provision_spire_child.terraform_operator_downstream["keycloak"].wrapper_name
    }
  }

  ansible_extra_vars = {
    keycloak_credential_kv_path = local.kv_paths["keycloak"]["frontend"].app
    vault_access                = jsonencode(local.vault_access)

    spire_server_port               = tostring(local.spire_parent.server_port)
    spire_parent_node_ip            = local.spire_parent.node_ip
    spire_parent_ssh_host           = local.spire_parent.ssh_host
    spire_trust_domain              = local.spire_parent.trust_domain
    spire_workload_spiffe_id        = local.spire_workload_spiffe_id
    spire_cluster_name              = module.context.svc_identity.cluster_name
    spire_parent_join_token_kv_path = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths["spire"]["parent"].join_token
    spire_child_join_token_kv_path  = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths["spire"]["child"].join_token

    spire_child_agent_address      = local.state.provision_spire_child.spire_child_agent_endpoint.address
    spire_child_agent_port         = tostring(local.state.provision_spire_child.spire_child_agent_endpoint.port)
    spire_child_kubeconfig_kv_path = local.state.provision_spire_child.spire_child_registrar_kv_path
    vault_agent_jwt_audience       = local.tenant_login.audience

    vault_agent_common_name     = local.sec_vault_agent_identity.common_name
    bastion_vault_ca_cert_path  = local.state.foundation_vault_bastion.bastion_vault.listener_ca_cert_path
    bastion_operator_wrapper    = local.terraform_operator.wrapper_name
    bastion_operator_role       = local.terraform_operator.role_name
    bastion_operator_auth_mount = local.state.platform_spire_parent.spire_oidc_auth_backend_path
  }
}
