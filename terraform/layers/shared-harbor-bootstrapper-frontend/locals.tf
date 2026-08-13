
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

# Provider prerequisites: Must be defined as root-level locals because provider blocks cannot reference module outputs.
locals {
  sys_vault_endpoint  = "https://${data.terraform_remote_state.security_vault_approle.outputs.prod_vault_svc_vip}:443"
  vault_pki_cert_path = data.terraform_remote_state.security_pki.outputs.bastion_pki_chain_b64.path
}

# Vault Agent identity
locals {
  sec_vault_agent_identity = merge(module.context.vault_agent_identity_base, {
    secret_id = vault_approle_auth_backend_role_secret_id.bootstrap_harbor_agent.secret_id
  })
}

# Ansible Configuration
locals {
  ansible_template_vars = {
    service_identifier                 = module.context.primary_context.s_name
    harbor_bootstrapper_fqdn           = module.context.svc_fqdn
    harbor_bootstrapper_service_domain = module.context.svc_identity.cluster_name

    harbor_bootstrapper_vip              = module.context.primary_net_config.lb_config.vip
    harbor_bootstrapper_tls_port         = module.context.primary_net_config.lb_config.ports["https"].frontend_port
    harbor_bootstrapper_mtls_node_subnet = module.context.primary_net_config.network.hostonly.cidr
    vault_vip                            = data.terraform_remote_state.load_balancer.outputs.infrastructure_vips["vault-frontend"]
    global_mss                           = module.context.global_mss
    harbor_metrics_port                  = data.terraform_remote_state.load_balancer.outputs.global_topology_network["harbor-bootstrapper"]["frontend"].ports["metrics"].frontend_port

    harbor_bootstrapper_cluster_ips = flatten([
      for comp_name, comp_config in var.service_config : [
        for node_suffix, node_data in comp_config.nodes :
        cidrhost(module.context.primary_net_config.network.hostonly.cidr, node_data.ip_suffix)
      ]
    ])

    harbor_bootstrapper_static_routes = [
      for name, vip in data.terraform_remote_state.load_balancer.outputs.infrastructure_vips : {
        to     = "${vip}/32"
        via    = module.context.primary_net_config.lb_config.vip
        metric = 100
      }
      if contains([
        "vault-frontend", "keycloak-frontend",
        "harbor-bootstrapper-frontend"
      ], name)
    ]

    access_scope = module.context.primary_net_config.network.hostonly.cidr
    service_name = module.context.primary_context.s_name
  }

  ansible_extra_vars = {
    vault_agent_common_name = local.sec_vault_agent_identity.common_name
    vault_agent_cert_ttl    = data.terraform_remote_state.security_pki.outputs.prod_pki_configuration.lease_durations.agent
  }
}
