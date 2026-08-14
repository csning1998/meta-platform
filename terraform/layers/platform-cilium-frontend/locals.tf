
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    network         = data.terraform_remote_state.network.outputs
    vault_bootstrap = data.terraform_remote_state.vault_bootstrapper.outputs
  }
  vault_kv_namespace = "meta-platform"
}

# segments_map is reused from shared-load-balancer-frontend.
# The service catalog owns segments_map, not HAProxy or Cilium.
locals {
  segments_map = merge([
    for s_name, components in local.state.network.global_topology_identity : {
      for c_name, identity in components : identity.cluster_name => {
        identity = identity
        network  = local.state.network.global_topology_network[s_name][c_name]
        vip      = lookup(local.state.network.infrastructure_map, identity.cluster_name, { lb_config = { vip = null } }).lb_config.vip
        s_name   = s_name
        c_name   = c_name
      }
    }
  ]...)

  infrastructure_vips = {
    for k, v in local.segments_map : "${v.s_name}-${v.c_name}" => v.vip
    if v.vip != null
  }

  network_map = { for k, v in local.segments_map : k => v.network }

  # Target cluster context
  svc_cluster_name = var.target_cluster_name
  svc_context      = local.segments_map[local.svc_cluster_name]
  svc_fqdn         = local.state.network.global_domain_suffix
  svc_identity     = local.svc_context.identity
  svc_network      = local.svc_context.network
  svc_node_prefix  = local.svc_identity.node_name_prefix

  # Cluster-wide network configuration
  net_lb_config = local.state.network.infrastructure_map[local.svc_cluster_name].network

  # net_service_segments excludes the CLB cluster, which has no SSoT reservation.
  # The same defect exists on shared-load-balancer-frontend and remains open.
  net_service_segments = [
    for name, seg in local.state.network.service_segments : merge(seg, {
      node_ips = {
        for node_name, node_spec in var.node_config : local.net_node_naming_map[node_name] =>
        cidrhost(seg.cidr, node_spec.ip_suffix)
      }
    })
    if seg.name != local.svc_cluster_name && !contains(seg.tags, "self-managed-lb")
  ]

  # net_node_naming_map re-keys tfvars keys such as "00" to "${svc_node_prefix}-NN".
  # Downstream modules consume net_node_naming_map values.
  net_sorted_node_keys = sort(keys(var.node_config))
  net_node_naming_map = {
    for idx, key in local.net_sorted_node_keys :
    key => "${local.svc_node_prefix}-${format("%02d", idx)}"
  }
}

locals {
  talos_iso_path = abspath("${path.root}/../../../packer/output/talos-${trimprefix(var.talos_version, "v")}/metal-amd64.iso")
}

check "talos_iso_present" {
  assert {
    condition     = fileexists(local.talos_iso_path)
    error_message = "Talos ISO missing at ${local.talos_iso_path}. Build it via packer before applying this layer."
  }
}
