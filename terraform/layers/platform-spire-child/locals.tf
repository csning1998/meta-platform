
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
  terraform_operator = local.state.provision_spire_parent.terraform_operator["spire-child"]
}

locals {
  svc_identity     = local.state.foundation_libvirt_resources.foundation_topology.identity["spire"]["child"]
  svc_network      = local.state.foundation_libvirt_resources.foundation_topology.network["spire"]["child"]
  net_lb_config    = local.state.foundation_libvirt_resources.foundation_topology.infrastructure[local.svc_cluster_name].network
  net_mtu          = local.state.foundation_libvirt_resources.foundation_global.network_baseline.global_mtu
  svc_fqdn         = local.state.foundation_libvirt_resources.foundation_global.domain_suffix
  svc_cluster_name = local.svc_identity.cluster_name
  svc_node_prefix  = local.svc_identity.node_name_prefix

  # Network map binds cluster network definition solely to the dedicated SPIRE child cluster name.
  network_map = { (local.svc_cluster_name) = local.svc_network }

  # net_node_naming_map re-keys tfvars keys such as "00" to "${svc_node_prefix}-NN".
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

check "node_count_matches_catalog" {
  assert {
    condition     = length(var.node_config) == length(local.state.foundation_libvirt_resources.foundation_topology.network["spire"]["child"].node_ips)
    error_message = "node_config MUST declare one node per address of the spire child ip_range in the service catalog."
  }
}
