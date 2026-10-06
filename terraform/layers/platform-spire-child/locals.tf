
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    foundation_libvirt_resources      = data.terraform_remote_state.foundation_libvirt_resources.outputs
    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
  }
}

locals {
  # The operator of the SPIRE Child logs in to the Downstream Vault with the JWT-SVID of the SPIRE Parent.
  terraform_operator_subject = { service = "spire", component = "child" }
  terraform_operator         = local.state.security_vault_downstream_tenants.downstream_vault_operators[local.terraform_operator_subject.service][local.terraform_operator_subject.component]

  spire_child_cluster_identity = local.state.foundation_libvirt_resources.foundation_topology.identity["spire"]["child"]
  spire_child_cluster_network  = local.state.foundation_libvirt_resources.foundation_topology.network["spire"]["child"]
  spire_child_cluster_name     = local.spire_child_cluster_identity.cluster_name
}

# The SPIRE Child precedes Harbor Origin, hence the chart and the images of this cluster come from the upstream registries.
locals {
  spire_child_chart_repository = "oci://quay.io/cilium/charts"
}
