
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    foundation_libvirt_resources = data.terraform_remote_state.foundation_libvirt_resources.outputs
    platform_spire_parent        = data.terraform_remote_state.platform_spire_parent.outputs
  }
}

locals {
  project_code = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
  identity     = local.state.foundation_libvirt_resources.foundation_topology.identity
  kv_paths     = local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths

  # The workstation agents register under this cluster name on both SPIRE servers.
  workstation_cluster_name = "host-terraform-operator"
}

locals {
  # Components whose Terraform operator layers run from the local machine and log in to the Downstream Vault with a JWT-SVID,
  # keyed by the name which consumer layers look up in output terraform_operator.
  # The vault-downstream operator administers the Downstream Vault alone, since a tenant session carries every Bastion change.
  _spire_operator_targets = {
    "cilium"           = { service = "cilium", component = "hubble" }
    "harbor-origin"    = { service = "harbor-origin", component = "frontend" }
    "keycloak"         = { service = "keycloak", component = "frontend" }
    "spire-child"      = { service = "spire", component = "child" }
    "vault-downstream" = { service = "vault-downstream", component = "frontend" }
  }

  # A target absent from foundation-libvirt-resources renders as a missing key here
  # instead of an opaque "Invalid index" crash in spire_terraform_operator_specs.
  _spire_operator_targets_missing = [
    for key, t in local._spire_operator_targets :
    key if !contains(keys(lookup(local.identity, t.service, {})), t.component)
  ]

  # Keyed by the identity string of the operator, <owner>-terraform-operator-<service>-<component>, which also names
  # the role and the policy of the operator on the Downstream Vault.
  spire_terraform_operator_specs = {
    for key, t in local._spire_operator_targets :
    "${local.project_code}-terraform-operator-${t.service}-${t.component}" => {
      output_key   = key
      service      = t.service
      component    = t.component
      spiffe_path  = "/${local.project_code}/terraform-operator/${t.service}/${t.component}"
      cluster_name = local.identity[t.service][t.component].cluster_name
    }
    if !contains(local._spire_operator_targets_missing, key)
  }
}

locals {
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

  # The plays take the Vault address, the CA path, and the token from the tenant session.
  ansible_extra_vars = {
    operator_vault_use_ambient_token               = true
    spire_jwt_issuer                               = local.state.platform_spire_parent.spire_oidc_discovery_url
    spire_parent_join_token_kv_path                = local.kv_paths["spire"]["parent"].join_token
    spire_child_join_token_kv_path                 = local.kv_paths["spire"]["child"].join_token
    utils_terraform_operator_identity_names        = jsonencode(keys(local.spire_terraform_operator_specs))
    utils_terraform_operator_identity_spiffe_paths = jsonencode({ for name, spec in local.spire_terraform_operator_specs : name => spec.spiffe_path })
  }
}
