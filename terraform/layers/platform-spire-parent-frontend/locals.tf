
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  ansible_template_config = {
    global_mss                 = module.context.global_mss
    spire_parent_vip           = module.context.primary_net_config.lb_config.vip
    spire_parent_node_ip       = one(module.context.svc_network.node_ips)
    spire_parent_cluster_name  = module.context.svc_identity.cluster_name
    spire_parent_static_routes = one(values(module.context.asymmetric_static_routes))
  }

  ansible_extra_config = {
    ansible_user = module.context.sec_vm_credentials.username
  }
}
