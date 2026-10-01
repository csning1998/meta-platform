
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  state = {
    foundation_libvirt_resources = data.terraform_remote_state.foundation_libvirt_resources.outputs
    foundation_vault_bastion     = data.terraform_remote_state.foundation_vault_bastion.outputs
    platform_spire_parent        = data.terraform_remote_state.platform_spire_parent.outputs
  }
}

locals {
  project_code = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
}

locals {
  # The workstation agents register under this cluster name on both SPIRE servers.
  workstation_cluster_name = "host-terraform-operator"

  kv_paths    = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths
  kv_leaf_ssh = basename(local.kv_paths["spire"]["parent"].ssh)

  ansible_config = {
    root_path      = abspath("${path.root}/../../../ansible")
    inventory_file = "inventory-provision-spire-parent-frontend-operator.yaml"
  }

  inventory_data = {
    all = {
      hosts = {
        "host-terraform-operator-workstation" = {
          ansible_connection = "local"
          node_role          = "host_terraform_operator"
        }
      }
      vars = {
        ansible_python_interpreter = "/usr/bin/python3"
        spire_cluster_name         = local.workstation_cluster_name
        spire_trust_domain         = local.state.platform_spire_parent.spire_agent_bootstrap.trust_domain
        spire_parent_node_ip       = local.state.platform_spire_parent.spire_agent_bootstrap.node_ip
        spire_parent_ssh_host      = local.state.platform_spire_parent.spire_agent_bootstrap.ssh_host
        spire_server_port          = tostring(local.state.platform_spire_parent.spire_agent_bootstrap.server_port)
      }
    }
  }

  ansible_extra_vars = {
    bastion_vault_ca_cert_path                     = local.state.foundation_vault_bastion.bastion_vault.listener_ca_cert_path
    bastion_vault_endpoint                         = local.state.foundation_vault_bastion.bastion_vault.endpoint
    bastion_vault_use_ambient_token                = true
    spire_parent_join_token_kv_path                = local.kv_paths["spire"]["parent"].join_token
    spire_child_join_token_kv_path                 = local.kv_paths["spire"]["child"].join_token
    spire_oidc_auth_path                           = local.state.platform_spire_parent.spire_oidc_auth_backend_path
    utils_terraform_operator_identity_names        = jsonencode(keys(local.spire_terraform_operator_specs))
    utils_terraform_operator_identity_spiffe_paths = jsonencode({ for name, spec in local.spire_terraform_operator_specs : name => spec.spiffe_path })
  }
}

locals {
  # Components whose Terraform operator layers run from the local machine and require a SPIRE-backed
  # JWT auth role on the Bastion Vault, keyed by the name which consumer layers look up in output terraform_operator.
  # Add an entry only when a corresponding platform-* or provision-* consumer layer exists.
  _spire_operator_targets = {
    "cilium"           = { service = "cilium", component = "frontend" }
    "harbor-origin"    = { service = "harbor-origin", component = "frontend" }
    "vault-downstream" = { service = "vault-downstream", component = "frontend" }
    "haproxy"          = { service = "haproxy", component = "frontend" }
    "keycloak"         = { service = "keycloak", component = "frontend" }
    "spire-child"      = { service = "spire", component = "child" }
  }

  # A target absent from foundation-libvirt-resources renders as a missing key here
  # instead of an opaque "Invalid index" crash in spire_terraform_operator_specs.
  _spire_operator_targets_missing = [
    for key, t in local._spire_operator_targets :
    key if try(local.state.foundation_libvirt_resources.foundation_topology.identity[t.service][t.component], null) == null
  ]

  # Keyed by the identity string of the operator, <owner>-terraform-operator-<service>-<component>.
  # Every name below derives from the owner code and the foundation-libvirt-resources SSoT outputs.
  spire_terraform_operator_specs = {
    for key, t in local._spire_operator_targets :
    "${local.project_code}-terraform-operator-${t.service}-${t.component}" => {
      output_key  = key
      spiffe_path = "/${local.project_code}/terraform-operator/${t.service}/${t.component}"
      # The consumer names its own workload role, policy, and Bastion PKI role by its cluster_name.
      cluster_name    = local.state.foundation_libvirt_resources.foundation_topology.identity[t.service][t.component].cluster_name
      kv_service_path = "secret/data/${local.state.foundation_libvirt_resources.foundation_vault_path.credential_paths[t.service][t.component]}"
    }
    if !contains(local._spire_operator_targets_missing, key)
  }
}

check "spire_operator_targets_exist" {
  assert {
    condition     = length(local._spire_operator_targets_missing) == 0
    error_message = "_spire_operator_targets names a component which foundation-libvirt-resources lacks: ${join(", ", local._spire_operator_targets_missing)}."
  }
}
