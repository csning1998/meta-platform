
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    platform_cilium_hubble       = data.terraform_remote_state.platform_cilium_hubble.outputs
    foundation_libvirt_resources = data.terraform_remote_state.foundation_libvirt_resources.outputs

    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    security_vault_downstream_pki     = data.terraform_remote_state.security_vault_downstream_pki.outputs
  }
}

locals {
  cluster_issuer   = local.state.platform_cilium_hubble.cluster_issuer
  external_secrets = local.state.platform_cilium_hubble.external_secrets


  infrastructure_map = local.state.foundation_libvirt_resources.foundation_topology.infrastructure
  project_code       = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
}

locals {
  kubeconfig   = yamldecode(base64decode(ephemeral.vault_kv_secret_v2.cilium_hubble.data["content_b64"]))
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
  cilium_cluster_name = local.state.foundation_libvirt_resources.foundation_topology.identity["cilium"]["hubble"].cluster_name

  # Kubernetes-native runtimes only. Any other runtime is an external service owned end to
  # end by platform-haproxy-frontend, per the decisions.md entry retiring Cilium Service
  # exposure for non-Kubernetes backends. Registering both here and there double-owns the VIP.
  kubernetes_native_runtimes = local.state.foundation_libvirt_resources.foundation_topology.kubernetes_native_runtimes

  # Excludes entries missing an SSoT VIP (an open ADR defect) or a backend server, both
  # of which fail downstream against Cilium or the Kubernetes API.
  # A cluster tagged self-managed-lb holds its own VIP. An announcement of the VIP from this layer duplicates the holder.
  fronted_segments = {
    for key, seg in local.infrastructure_map : key => seg
    if key != local.cilium_cluster_name
    && !contains(seg.lb_config.tags, "self-managed-lb")
    && contains(local.kubernetes_native_runtimes, seg.runtime)
    && seg.lb_config.vip != null
    && length(seg.backend_servers) > 0
  }

  # Selector label binding generated Services to Cilium IPAM pools and L2 announcement
  # policies, isolating address allocations from unmanaged cluster workloads.
  lb_managed_label = {
    "platform.io/lb-managed" = "cilium-hubble"
  }
}

# The operator of this component logs in to the Downstream Vault with the JWT-SVID of the SPIRE Parent.
locals {
  downstream_operator = local.state.security_vault_downstream_tenants.component_operators["cilium"]
}
