
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    foundation_libvirt_resources       = data.terraform_remote_state.foundation_libvirt_resources.outputs
    platform_vault_downstream_frontend = data.terraform_remote_state.platform_vault_downstream_frontend.outputs
    platform_spire_parent              = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_parent             = data.terraform_remote_state.provision_spire_parent.outputs
  }
}

locals {
  project_code = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
  kv_paths     = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths
  trust_domain = local.state.platform_spire_parent.spire_agent_bootstrap.trust_domain

  downstream_vault = {
    endpoint       = local.state.platform_vault_downstream_frontend.vault_endpoint.address
    ca_cert_path   = local.state.platform_vault_downstream_frontend.vault_endpoint.ca_cert_path
    pki_mount_path = local.state.platform_vault_downstream_frontend.pki_identity.intermediate_mount_path
    # provision-vault-downstream-frontend writes the root token of the initialization to this KV path of the Bastion Vault.
    init_kv_path = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["vault-downstream"]["frontend"].init
  }

  # The SPIRE Parent mount keeps the audience vault, which the JWT-SVID wrappers of the workstation request.
  jwt_auth = {
    parent = {
      mount_path = vault_jwt_auth_backend.spire_parent.path
      audience   = "vault"
    }
  }

  # Each operator binds its exact SPIFFE ID. A glob over terraform-operator/* would let every component assume the administrator.
  terraform_operators = local.state.provision_spire_parent.terraform_operator

  # The workstation agents register under this cluster name on both SPIRE servers, as provision-spire-parent declares.
  workstation_cluster_name = "host-terraform-operator"
  tenant_operator          = local.terraform_operators["vault-downstream"]
  component_operators      = { for key, operator in local.terraform_operators : key => operator if key != "vault-downstream" }
}
