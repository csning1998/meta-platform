
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  state = {
    foundation_vault_bastion     = data.terraform_remote_state.foundation_vault_bastion.outputs
    foundation_libvirt_resources = data.terraform_remote_state.foundation_libvirt_resources.outputs
    platform_spire_parent        = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_parent       = data.terraform_remote_state.provision_spire_parent.outputs
  }
}

locals {
  project_code       = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
  kv_paths           = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["cilium"]["frontend"]
  terraform_operator = local.state.provision_spire_parent.terraform_operator["cilium"]
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

  infrastructure_vips = {
    for k, v in local.segments_map : "${v.s_name}-${v.c_name}" => v.vip
    if v.vip != null
  }

  network_map   = { for k, v in local.segments_map : k => v.network }
  net_lb_config = local.state.foundation_libvirt_resources.foundation_topology.infrastructure[local.svc_cluster_name].network
  net_mtu       = local.state.foundation_libvirt_resources.foundation_global.network_baseline.global_mtu

  svc_cluster_name = var.target_cluster_name
  svc_context      = local.segments_map[local.svc_cluster_name]
  svc_fqdn         = local.state.foundation_libvirt_resources.foundation_global.domain_suffix
  svc_identity     = local.svc_context.identity
  svc_network      = local.svc_context.network
  svc_node_prefix  = local.svc_identity.node_name_prefix

  # net_service_segments excludes the CLB cluster, which has no SSoT reservation.
  # The same defect exists on platform-haproxy-frontend and remains open.
  net_service_segments = [
    for name, seg in local.state.foundation_libvirt_resources.foundation_topology.segments : merge(seg, {
      node_ips = {
        for node_name, node_spec in var.node_config : local.net_node_naming_map[node_name] =>
        cidrhost(seg.cidr, node_spec.ip_suffix)
      }
    })
    if seg.name != local.svc_cluster_name && !contains(seg.tags, "self-managed-lb")
  ]

  # Maps raw node index keys to canonical node hostnames matching foundation naming conventions.
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

# In-cluster trust chain: cert-manager and External Secrets Operator authenticate to the Bastion Vault through the
# Kubernetes auth mount of this cluster. All names derive from the identity string of the cluster.
locals {
  cluster_issuer = {
    namespace       = "cert-manager"
    name            = "platform-cluster-issuer"
    service_account = "platform-cluster-issuer"
    auth_path       = "${local.svc_identity.cluster_name}-service-account-token-provider"
    role_name       = local.svc_identity.cluster_name
    pki_mount_path  = local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_mount_path
    issue_path      = "sign"
    ref = {
      group = "cert-manager.io"
      kind  = "ClusterIssuer"
      name  = "platform-cluster-issuer"
    }
  }

  external_secrets = {
    namespace       = "external-secrets"
    service_account = "external-secrets-vault"
    role_name       = "${local.svc_identity.cluster_name}-external-secrets"
  }

  # Helm template does not render the namespaces, hence the leading Namespace document. The shared module orders the manifests by key.
  extra_inline_manifests = {
    "cert-manager"     = "apiVersion: v1\nkind: Namespace\nmetadata:\n  name: ${local.cluster_issuer.namespace}\n---\n${data.helm_template.cert_manager.manifest}"
    "external-secrets" = "apiVersion: v1\nkind: Namespace\nmetadata:\n  name: ${local.external_secrets.namespace}\n---\n${data.helm_template.external_secrets.manifest}"
    "gateway-api"      = data.http.gateway_api_crds.response_body
  }

  # Each node takes the address at its position in the sorted node keys from the foundation derivation.
  bastion_network_nodes = {
    for idx, key in local.net_sorted_node_keys : key => {
      (local.state.foundation_libvirt_resources.foundation_bastion_network.network_name) = local.state.foundation_libvirt_resources.foundation_bastion_network.addresses[local.svc_cluster_name][idx]
    }
  }
}
