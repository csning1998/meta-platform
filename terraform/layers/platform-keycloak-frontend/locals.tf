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
    platform_spire_parent             = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_child             = data.terraform_remote_state.provision_spire_child.outputs
    provision_harbor_origin_frontend  = data.terraform_remote_state.provision_harbor_origin_frontend.outputs
  }
}

# Provider prerequisites: Must be defined as root-level locals because provider blocks cannot reference module outputs.
locals {
  downstream_vault_endpoint = "https://${local.state.security_vault_downstream_tenants.downstream_vault_service_vip}:443"
  vault_pki_cert_path       = local.state.security_vault_downstream_pki.bastion_pki_chain_b64.path
  harbor_registry_mirror    = local.state.provision_harbor_origin_frontend.harbor_registry_mirror
  downstream_kv_paths       = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths
}

# The runtime of the component in the service catalog selects the VM path or the Talos path.
locals {
  keycloak_cluster_name    = module.terraform_layer_context.cluster_identity.cluster_name
  keycloak_cluster_runtime = local.state.foundation_libvirt_resources.foundation_topology.infrastructure[local.keycloak_cluster_name].runtime
  is_runtime_talos         = contains(local.state.foundation_libvirt_resources.foundation_topology.kubernetes_native_runtimes, local.keycloak_cluster_runtime)
}

# The operator of this component logs in to the Downstream Vault with the JWT-SVID of the SPIRE Parent.
locals {
  keycloak_operator = local.state.security_vault_downstream_tenants.downstream_vault_component_operators["keycloak"]
}
