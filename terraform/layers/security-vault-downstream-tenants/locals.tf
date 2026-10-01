
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  state = {
    foundation_vault_bastion           = data.terraform_remote_state.foundation_vault_bastion.outputs
    foundation_libvirt_resources       = data.terraform_remote_state.foundation_libvirt_resources.outputs
    platform_vault_downstream_frontend = data.terraform_remote_state.platform_vault_downstream_frontend.outputs
    platform_spire_parent              = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_parent             = data.terraform_remote_state.provision_spire_parent.outputs
    provision_spire_child              = data.terraform_remote_state.provision_spire_child.outputs
  }
}

locals {
  project_code       = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
  cluster_name       = local.state.foundation_libvirt_resources.foundation_topology.identity["vault-downstream"]["frontend"].cluster_name
  terraform_operator = local.state.provision_spire_parent.terraform_operator["vault-downstream"]

  # Downstream Vault root initialization token path written by platform-vault-downstream-frontend.
  kv_paths = {
    init = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["vault-downstream"]["frontend"].init
  }

  downstream_vault = {
    endpoint       = local.state.platform_vault_downstream_frontend.endpoint
    ca_cert_path   = local.state.platform_vault_downstream_frontend.ca_cert_path
    pki_mount_path = local.state.platform_vault_downstream_frontend.pki_identity.intermediate_mount_path
  }

  # The Downstream Vault role for the workstation operator, bound on the Parent and the Child JWT mounts below.
  tenant_operator = {
    role_name  = "${local.project_code}-terraform-operator"
    spiffe_ids = "spiffe://${local.state.platform_spire_parent.spire_agent_bootstrap.trust_domain}/${local.project_code}/terraform-operator/*"
  }

  # The audience of the Child mount is the Downstream Vault cluster name, and the Parent mount keeps the audience vault.
  jwt_auth = {
    parent = {
      mount_path = vault_jwt_auth_backend.spire_parent.path
      audience   = "vault"
    }
    child = {
      mount_path = vault_jwt_auth_backend.spire_child.path
      audience   = local.cluster_name
    }
  }

  bastion_pki_chain_pem = "${local.state.foundation_vault_bastion.bastion_vault_pki.root_cert_pem}\n${local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_cert_pem}"
}
