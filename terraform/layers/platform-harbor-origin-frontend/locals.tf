
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    network       = data.terraform_remote_state.network.outputs
    vault_bastion = data.terraform_remote_state.vault_bastion.outputs
  }
  vault_kv_namespace = local.state.network.vault_kv_namespace
}

# Later Cilium announcement requires the catalog VIP in the certificate IP SAN.
locals {
  harbor_node_ips = flatten([
    for comp_name, comp_config in var.service_config : [
      for node_suffix, node_data in comp_config.nodes :
      cidrhost(module.context.primary_net_config.network.hostonly.cidr, node_data.ip_suffix)
    ]
  ])

  # Pin the bootstrap listener to the lowest node IP; map iteration order is not intent-bearing.
  harbor_listen_ip = sort(local.harbor_node_ips)[0]

  # The bootstrapping stage precedes Cilium VIP announcement.
  harbor_origin_stage = "bootstrapping"

  bastion_pki_chain_pem = "${local.state.vault_bastion.bastion_pki_root_cert_pem}\n${local.state.vault_bastion.bastion_pki_inter_cert_pem}"
  bastion_pki_listener_bundle = {
    server_cert_b64 = base64encode(vault_pki_secret_backend_cert.listener.certificate)
    server_key_b64  = base64encode(vault_pki_secret_backend_cert.listener.private_key)
    ca_cert_b64     = base64encode(local.bastion_pki_chain_pem)
  }
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

  harbor_origin_secrets = jsondecode(data.vault_kv_secret_v2.harbor_origin.data_json)

  ansible_extra_vars = {
    harbor_origin_stage          = local.harbor_origin_stage
    harbor_origin_admin_password = sensitive(local.harbor_origin_secrets["harbor_origin_admin_password"])
    harbor_origin_pg_db_password = sensitive(local.harbor_origin_secrets["harbor_origin_pg_db_password"])
  }
}
