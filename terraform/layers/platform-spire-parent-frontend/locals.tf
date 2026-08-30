
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  # The trust domain is "<stage>.<domain_suffix>". regex() asserts the PKI-issued
  # FQDN still has the "<service_name>.<stage>.<domain_suffix>" shape svc_fqdn was
  # built from; a mismatch fails plan instead of silently producing a wrong domain.
  spire_trust_domain = regex("^[^.]+\\.(${module.context.svc_identity.stage}\\..+)$", module.context.svc_fqdn)[0]
  spire_server_port  = module.context.primary_net_config.lb_config.ports.api.frontend_port

  ansible_template_config = {
    global_mss                 = module.context.global_mss
    spire_parent_vip           = module.context.primary_net_config.lb_config.vip
    spire_parent_node_ip       = one(module.context.svc_network.node_ips)
    spire_parent_cluster_name  = module.context.svc_identity.cluster_name
    spire_parent_static_routes = one(values(module.context.asymmetric_static_routes))
    spire_trust_domain         = local.spire_trust_domain
    spire_server_port          = local.spire_server_port
  }

  ansible_extra_config = {
    ansible_user = module.context.sec_vm_credentials.username
  }
}
