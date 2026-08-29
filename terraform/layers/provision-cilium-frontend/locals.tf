
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    cilium_frontend = data.terraform_remote_state.cilium_frontend.outputs
  }

  infrastructure_map = local.state.cilium_frontend.infrastructure_map
  vault_kv_namespace = "meta-platform"
}

locals {
  kubeconfig   = yamldecode(base64decode(ephemeral.vault_kv_secret_v2.cilium_frontend.data["content_b64"]))
  cluster_info = local.kubeconfig.clusters[0].cluster
  user_info    = local.kubeconfig.users[0].user

  api_server_connection = {
    host               = local.cluster_info.server
    ca_cert            = base64decode(local.cluster_info["certificate-authority-data"])
    client_certificate = base64decode(local.user_info["client-certificate-data"])
    client_key         = base64decode(local.user_info["client-key-data"])
  }
}

# Exclude the Cilium cluster segment from Service generation to prevent circular routing dependencies and self-referential load balancing.
locals {
  cilium_cluster_name = local.state.cilium_frontend.global_topology_identity["cilium"]["frontend"].cluster_name

  # Excludes entries missing an SSoT VIP (an open ADR defect) or a backend server, both
  # of which fail downstream against Cilium or the Kubernetes API.
  fronted_segments = {
    for key, seg in local.infrastructure_map : key => seg
    if key != local.cilium_cluster_name
    && seg.lb_config.vip != null
    && length(seg.backend_servers) > 0
  }

  # Selector label binding generated Services to Cilium IPAM pools and L2 announcement
  # policies, isolating address allocations from unmanaged cluster workloads.
  lb_managed_label = {
    "platform.io/lb-managed" = "cilium-frontend"
  }
}
