
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
  cluster_name       = local.state.network.global_topology_identity["haproxy"]["frontend"].cluster_name
}

# Kubernetes-native runtimes stay on the Cilium Service/L2Announcement path. Any other
# runtime in the catalog is an external service, owned end to end by this tier per the
# decisions.md entry retiring Cilium Service exposure for non-Kubernetes backends.
locals {
  kubernetes_native_runtimes = ["talos", "kubeadm", "microk8s", "minikube"]

  fronted_segments = {
    for key, seg in local.state.network.infrastructure_map : key => seg
    if key != local.cluster_name
    && !contains(local.kubernetes_native_runtimes, seg.runtime)
    && seg.lb_config.vip != null
    && length(seg.backend_servers) > 0
  }
}

# Each fronted segment becomes one extra NIC on every HAProxy node, attached to the
# already-existing hostonly network for that segment. A static per-node address keeps
# the Keepalived VRRP peer list deterministic without relying on DHCP.
locals {
  haproxy_extra_ip_offset = 240

  sorted_node_keys = sort(keys(var.service_config[var.primary_role].nodes))

  haproxy_extra_networks_by_node = {
    for idx, node_key in local.sorted_node_keys : node_key => {
      for seg_key, seg in local.fronted_segments :
      seg.network.hostonly.name => "${cidrhost(seg.network.hostonly.cidr, local.haproxy_extra_ip_offset + idx)}/${seg.network.hostonly.prefix}"
    }
  }

  service_config = {
    for role, cfg in var.service_config : role => merge(cfg, {
      nodes = {
        for node_key, node in cfg.nodes : node_key => merge(node, {
          extra_networks = role == var.primary_role ? local.haproxy_extra_networks_by_node[node_key] : {}
        })
      }
    })
  }
}

# Backend list for the platform_haproxy_frontend Ansible role, read from the same infrastructure_map
# feeding the Cilium manifests. Both stay derived from one Terraform source.
locals {
  lb_service_segments = [
    for seg_key, seg in local.fronted_segments : {
      name            = seg_key
      vip             = seg.lb_config.vip
      cidr            = seg.network.hostonly.cidr
      gateway         = seg.network.hostonly.gateway
      interface_alias = module.interface_alias[seg_key].alias
      vrid            = tonumber(split(".", seg.network.hostonly.cidr)[2])
      ports           = seg.lb_config.ports
      backend_servers = seg.backend_servers
    }
  ]

  fronted_segment_vrids = [for seg in local.lb_service_segments : seg.vrid]

  # extra_networks addresses HAProxy assigns itself on a fronted segment must not collide with
  # the backend node addresses or the VIP already reserved on that same segment.
  extra_network_offset_conflicts = flatten([
    for seg_key, seg in local.fronted_segments : [
      for idx in range(length(local.sorted_node_keys)) :
      seg_key
      if contains(
        concat([for server in seg.backend_servers : server.ip], [seg.lb_config.vip]),
        cidrhost(seg.network.hostonly.cidr, local.haproxy_extra_ip_offset + idx)
      )
    ]
  ])
}

check "haproxy_vrid_valid" {
  assert {
    condition     = alltrue([for v in local.fronted_segment_vrids : v >= 1 && v <= 255])
    error_message = "Every fronted segment's derived VRID must fall within the valid VRRP range [1, 255]."
  }
  assert {
    condition     = length(local.fronted_segment_vrids) == length(distinct(local.fronted_segment_vrids))
    error_message = "Two fronted segments derived the same VRID; VRRP requires a unique virtual_router_id per L2 segment."
  }
}

check "haproxy_extra_network_offsets_safe" {
  assert {
    condition     = length(local.extra_network_offset_conflicts) == 0
    error_message = "haproxy_extra_ip_offset collides with a fronted segment's own reserved node ip_range for: ${join(", ", local.extra_network_offset_conflicts)}."
  }
}

locals {
  bastion_pki_chain_pem = "${local.state.vault_bastion.bastion_pki_root_cert_pem}\n${local.state.vault_bastion.bastion_pki_inter_cert_pem}"

  # ansible_host resolves through the operator SSH config alias, meaningless inside the
  # guest. The stats listener needs the real address on this segment.
  haproxy_node_ips = [
    for node_key, node in var.service_config[var.primary_role].nodes :
    cidrhost(module.context.primary_net_config.network.hostonly.cidr, node.ip_suffix)
  ]
  haproxy_listen_address = sort(local.haproxy_node_ips)[0]

  ansible_template_config = {
    global_mss   = module.context.global_mss
    access_scope = module.context.primary_net_config.network.hostonly.cidr
  }

  ansible_extra_config = {
    lb_service_segments      = jsonencode(local.lb_service_segments)
    vault_haproxy_bundle_b64 = base64encode("${vault_pki_secret_backend_cert.stats.certificate}\n${vault_pki_secret_backend_cert.stats.private_key}\n")
    vault_ca_cert_b64        = base64encode("${local.bastion_pki_chain_pem}\n")
    haproxy_stats_port       = module.context.primary_net_config.lb_config.ports["stats"].frontend_port
    haproxy_listen_address   = local.haproxy_listen_address
    keepalived_auth_pass     = module.keepalived_credential.credentials["keepalived_auth_pass"]

    spire_server_port              = tostring(local.state.spire_parent.spire_agent_bootstrap.server_port)
    spire_parent_node_ip           = local.state.spire_parent.spire_agent_bootstrap.node_ip
    spire_parent_ssh_host          = local.state.spire_parent.spire_agent_bootstrap.ssh_host
    spire_trust_domain             = local.state.spire_parent.spire_agent_bootstrap.trust_domain
    spire_cluster_name             = module.context.svc_identity.cluster_name
    spire_workload_spiffe_id       = local.spire_workload_spiffe_id
    spire_oidc_auth_path           = local.state.spire_parent.spire_oidc_auth_backend_path
    spire_workload_vault_role_name = module.spire_workload_identity.role_name

    vault_endpoint             = local.state.vault_bastion.bastion_vault_endpoint
    vault_role_name            = local.haproxy_pki_role_name
    vault_pki_mount_path       = local.state.vault_bastion.bastion_pki_inter_mount_path
    vault_listener_ca_cert_b64 = filebase64(local.state.vault_bastion.bastion_vault_listener_ca_cert_path)
    vault_agent_common_name    = module.context.svc_fqdn
    vault_intermediate_ca_b64  = base64encode(local.bastion_pki_chain_pem)
  }

  spire_workload_spiffe_id = "spiffe://${local.state.spire_parent.spire_agent_bootstrap.trust_domain}/${module.context.svc_identity.cluster_name}"
  haproxy_pki_role_name    = module.context.primary_context.pki_key
}
