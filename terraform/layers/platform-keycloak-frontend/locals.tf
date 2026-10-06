
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    foundation_libvirt_resources      = data.terraform_remote_state.foundation_libvirt_resources.outputs
    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    security_vault_downstream_pki     = data.terraform_remote_state.security_vault_downstream_pki.outputs
    platform_spire_parent             = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_child             = data.terraform_remote_state.provision_spire_child.outputs
    provision_harbor_origin_frontend  = data.terraform_remote_state.provision_harbor_origin_frontend.outputs
  }
}

# Provider prerequisites: Must be defined as root-level locals because provider blocks cannot reference module outputs.
locals {
  sys_vault_endpoint  = "https://${local.state.security_vault_downstream_tenants.service_vip}:443"
  vault_pki_cert_path = local.state.security_vault_downstream_pki.bastion_pki_chain_b64.path
  registry_mirror     = local.state.provision_harbor_origin_frontend.registry_mirror
}

locals {
  kv_paths = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths
}

# The runtime of the component in the service catalog selects the VM path or the Talos path.
locals {
  svc_cluster_name = module.terraform_layer_context.svc_identity.cluster_name
  svc_runtime      = local.state.foundation_libvirt_resources.foundation_topology.infrastructure[local.svc_cluster_name].runtime
  is_runtime_talos = contains(local.state.foundation_libvirt_resources.foundation_topology.kubernetes_native_runtimes, local.svc_runtime)
}

locals {
  # Configures VM Vault Agent workload authentication using SPIRE Child JWT-SVID credentials.
  tenant_login = local.state.security_vault_downstream_tenants.downstream_tenants.tenant_login[module.terraform_layer_context.svc_identity.cluster_name]

  sec_vault_agent_identity = merge(module.terraform_layer_context.vault_agent_identity_base, {
    auth_path      = local.tenant_login.auth_mount
    auth_role_name = local.tenant_login.role_name
  })

  spire_parent             = local.state.platform_spire_parent.spire_agent_bootstrap
  spire_workload_spiffe_id = "spiffe://${local.spire_parent.trust_domain}/${local.state.security_vault_downstream_tenants.foundation_vault_path.project_code}/${module.terraform_layer_context.primary_context.s_name}/${module.terraform_layer_context.primary_context.c_name}"
}

locals {
  ansible_template_vars = {
    service_identifier      = module.terraform_layer_context.primary_context.s_name
    keycloak_fqdn           = module.terraform_layer_context.svc_fqdn
    keycloak_service_domain = module.terraform_layer_context.svc_identity.cluster_name
    keycloak_vip            = module.terraform_layer_context.primary_net_config.lb_config.vip
    keycloak_port           = module.terraform_layer_context.primary_net_config.lb_config.ports["https"].frontend_port
    keycloak_node_subnet    = module.terraform_layer_context.primary_net_config.network.hostonly.cidr
    vault_vip               = module.terraform_layer_context.prod_vault_svc_vip
    global_mss              = module.terraform_layer_context.global_mss

    infra_keycloak_cluster_ips = [
      for comp_name, comp_config in var.service_config : [
        for node_suffix, node_data in comp_config.nodes :
        cidrhost(module.terraform_layer_context.primary_net_config.network.hostonly.cidr, node_data.ip_suffix)
      ]
    ][0]

    access_scope = module.terraform_layer_context.primary_net_config.network.hostonly.cidr
    service_name = module.terraform_layer_context.primary_context.s_name
  }

  # Vault access configuration for Ansible operator login and secret retrieval.
  vault_access = {
    downstream = {
      endpoint     = local.state.security_vault_downstream_tenants.endpoint
      ca_cert_path = local.state.security_vault_downstream_tenants.ca_cert_path
      auth_mount   = local.downstream_operator.auth_mount
      role         = local.downstream_operator.role_name
      wrapper      = local.downstream_operator.wrapper_name
    }
  }

  ansible_extra_vars = {
    keycloak_credential_kv_path = local.kv_paths["keycloak"]["frontend"].app
    vault_access                = jsonencode(local.vault_access)

    spire_trust_domain             = local.spire_parent.trust_domain
    spire_workload_spiffe_id       = local.spire_workload_spiffe_id
    spire_cluster_name             = module.terraform_layer_context.svc_identity.cluster_name
    spire_child_join_token_kv_path = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths["spire"]["child"].join_token

    spire_child_agent_address      = local.state.provision_spire_child.spire_child_agent_endpoint.address
    spire_child_agent_port         = tostring(local.state.provision_spire_child.spire_child_agent_endpoint.port)
    spire_child_kubeconfig_kv_path = local.state.provision_spire_child.spire_child_registrar_kv_path
    vault_agent_jwt_audience       = local.tenant_login.audience

    vault_agent_common_name = local.sec_vault_agent_identity.common_name
    # The join tokens and the registrar kubeconfig of the SPIRE Child live in the Downstream KV.
    operator_vault_url          = local.state.security_vault_downstream_tenants.endpoint
    operator_vault_ca_cert_path = local.state.security_vault_downstream_tenants.ca_cert_path
    operator_vault_wrapper      = local.downstream_operator.wrapper_name
    operator_vault_role         = local.downstream_operator.role_name
    operator_vault_auth_mount   = local.downstream_operator.auth_mount
  }
}

# The operator of this component logs in to the Downstream Vault with the JWT-SVID of the SPIRE Parent.
locals {
  downstream_operator = local.state.security_vault_downstream_tenants.component_operators["keycloak"]
}
