
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    network       = data.terraform_remote_state.network.outputs
    vault_bastion = data.terraform_remote_state.vault_bastion.outputs
    spire_parent  = data.terraform_remote_state.spire_parent.outputs
  }
  vault_kv_namespace = local.state.network.vault_kv_namespace
}

# Requires inclusion of the catalog service VIP within the certificate IP SAN to support downstream Cilium service announcements.
locals {
  harbor_node_ips = flatten([
    for comp_name, comp_config in var.service_config : [
      for node_suffix, node_data in comp_config.nodes :
      cidrhost(module.context.primary_net_config.network.hostonly.cidr, node_data.ip_suffix)
    ]
  ])

  # Binds the bootstrap listener deterministically to the lowest numerical node IP, bypassing non-deterministic map iteration order.
  harbor_listen_ip = sort(local.harbor_node_ips)[0]

  # Specifies "bootstrapping" stage state pending live Cilium VIP announcement required for "registered" status.
  # Execution of utils_spire_agent SHALL NOT be gated by this stage.
  harbor_origin_stage = "bootstrapping"

  bastion_pki_chain_pem = "${local.state.vault_bastion.bastion_pki_root_cert_pem}\n${local.state.vault_bastion.bastion_pki_inter_cert_pem}"
  bastion_pki_listener_bundle = {
    server_cert_b64 = base64encode(vault_pki_secret_backend_cert.listener.certificate)
    server_key_b64  = base64encode(vault_pki_secret_backend_cert.listener.private_key)
    ca_cert_b64     = base64encode(local.bastion_pki_chain_pem)
  }

  spire_workload_spiffe_id = "spiffe://${local.state.spire_parent.spire_agent_bootstrap.trust_domain}/${module.context.svc_identity.cluster_name}"
  harbor_pki_role_name     = "harbor-origin-frontend"
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
    harbor_metrics_port            = module.context.primary_net_config.lb_config.ports["metrics"].frontend_port
    harbor_origin_listen_address   = local.harbor_listen_ip
    harbor_origin_cluster_ips      = local.harbor_node_ips
    harbor_origin_stage            = local.harbor_origin_stage
  }

  harbor_origin_secrets = data.vault_generic_secret.harbor_origin.data

  ansible_extra_vars = {
    harbor_origin_stage          = local.harbor_origin_stage
    harbor_origin_admin_password = sensitive(local.harbor_origin_secrets["harbor_origin_admin_password"])
    harbor_origin_pg_db_password = sensitive(local.harbor_origin_secrets["harbor_origin_pg_db_password"])
    spire_parent_node_ip         = local.state.spire_parent.spire_agent_bootstrap.node_ip
    spire_trust_domain           = local.state.spire_parent.spire_agent_bootstrap.trust_domain
    spire_server_port            = tostring(local.state.spire_parent.spire_agent_bootstrap.server_port)
    spire_cluster_name           = module.context.svc_identity.cluster_name

    spire_workload_spiffe_id       = local.spire_workload_spiffe_id
    spire_oidc_auth_path           = local.state.spire_parent.spire_oidc_auth_backend_path
    spire_workload_vault_role_name = module.spire_workload_identity.role_name

    vault_endpoint             = local.state.vault_bastion.bastion_vault_endpoint
    vault_role_name            = local.harbor_pki_role_name
    vault_pki_mount_path       = local.state.vault_bastion.bastion_pki_inter_mount_path
    vault_listener_ca_cert_b64 = filebase64(local.state.vault_bastion.bastion_vault_listener_ca_cert_path)
    vault_agent_common_name    = module.context.svc_fqdn
  }
}
