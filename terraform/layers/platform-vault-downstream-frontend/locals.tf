
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    foundation_libvirt_resources = data.terraform_remote_state.foundation_libvirt_resources.outputs
  }
  project_code = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
}

# Each registry field holds one category in JSON. The facts are not secret, while the provider marks every KV value as sensitive.
locals {
  registry_bastion = {
    for field, value in nonsensitive(data.vault_generic_secret.registry_bastion.data) : field => jsondecode(value)
  }
  bastion_pki_platform = local.registry_bastion.pki.constrained_intermediates["pki-platform"]

  # The listener of the Downstream Vault chains to the Bastion root through pki-platform.
  listener_ca_chain_pem = "${trimspace(local.registry_bastion.pki.root_cert_pem)}\n${trimspace(local.bastion_pki_platform.cert_pem)}\n"
}

# The runtime of the component in the service catalog selects the declarations of runtime-talos.tf or runtime-vm.tf.
locals {
  svc_cluster_name = module.terraform_layer_context.svc_identity.cluster_name
  svc_runtime      = local.state.foundation_libvirt_resources.foundation_topology.infrastructure[local.svc_cluster_name].runtime
  is_runtime_talos = contains(local.state.foundation_libvirt_resources.foundation_topology.kubernetes_native_runtimes, local.svc_runtime)
  kv_paths         = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["vault-downstream"]["frontend"]
}
