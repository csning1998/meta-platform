
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
    provision_harbor_origin_frontend  = data.terraform_remote_state.provision_harbor_origin_frontend.outputs
  }
}

locals {
  kv_paths            = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["cilium"]["hubble"]
  downstream_kv_paths = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths["cilium"]["hubble"]
}

# Provider prerequisites: Must be defined as root-level locals because provider blocks cannot reference module outputs.
locals {
  sys_vault_endpoint   = local.state.security_vault_downstream_tenants.endpoint
  vault_pki_cert_path  = local.state.security_vault_downstream_tenants.ca_cert_path
  harbor_robot_kv_path = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths["harbor-origin"]["frontend"].robot
  registry_mirror      = local.state.provision_harbor_origin_frontend.registry_mirror
}

# segments_map is reused from platform-haproxy-frontend.
# The service catalog owns segments_map, not HAProxy or Cilium.
locals {
  segments_map = merge([
    for s_name, components in local.state.foundation_libvirt_resources.foundation_topology.identity : {
      for c_name, identity in components : identity.cluster_name => {
        identity = identity
        network  = local.state.foundation_libvirt_resources.foundation_topology.network[s_name][c_name]
        vip      = lookup(local.state.foundation_libvirt_resources.foundation_topology.infrastructure, identity.cluster_name, { lb_config = { vip = null } }).lb_config.vip
        s_name   = s_name
        c_name   = c_name
      }
    }
  ]...)


  network_map = { for k, v in local.segments_map : k => v.network }

  svc_cluster_name = var.talos_config.target_cluster_name
  svc_context      = local.segments_map[local.svc_cluster_name]
  svc_identity     = local.svc_context.identity
  svc_pki          = local.state.foundation_libvirt_resources.foundation_pki.map["${local.svc_context.s_name}-${local.svc_context.c_name}"]

  # net_service_segments excludes the CLB cluster, which has no SSoT reservation.
  # The same defect exists on platform-haproxy-frontend and remains open.
  net_service_segments = [
    for name, seg in local.state.foundation_libvirt_resources.foundation_topology.segments : seg
    if seg.name != local.svc_cluster_name && !contains(seg.tags, "self-managed-lb")
  ]

  # Each node takes the address at its position in the sorted node keys from the foundation derivation.
  bastion_network_nodes = {
    for idx, key in sort(keys(var.node_config)) : key => {
      (local.state.foundation_libvirt_resources.foundation_bastion_network.network_name) = local.state.foundation_libvirt_resources.foundation_bastion_network.addresses[local.svc_cluster_name][idx]
    }
  }
}

# The operator of this component logs in to the Downstream Vault with the JWT-SVID of the SPIRE Parent.
locals {
  downstream_operator = local.state.security_vault_downstream_tenants.component_operators["cilium"]
}
