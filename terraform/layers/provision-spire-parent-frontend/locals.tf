
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    metadata      = data.terraform_remote_state.metadata.outputs
    vault_bastion = data.terraform_remote_state.vault_bastion.outputs
    spire_parent  = data.terraform_remote_state.spire_parent.outputs
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
        "host-terraform-operator-node-00" = {
          ansible_connection = "local"
          node_role          = "host_terraform_operator"
        }
      }
      vars = {
        ansible_python_interpreter = "/usr/bin/python3"
        spire_cluster_name         = "host-terraform-operator"
        spire_trust_domain         = local.state.spire_parent.spire_agent_bootstrap.trust_domain
        spire_parent_node_ip       = local.state.spire_parent.spire_agent_bootstrap.node_ip
        spire_parent_ssh_host      = local.state.spire_parent.spire_agent_bootstrap.ssh_host
        spire_server_port          = tostring(local.state.spire_parent.spire_agent_bootstrap.server_port)
      }
    }
  }

  ansible_extra_vars = {
    utils_terraform_operator_identity_names = jsonencode(keys(local.spire_terraform_operator_specs))
  }
}

locals {
  # Services whose Terraform operator layers run from the local machine and require a SPIRE-backed
  # JWT auth role on the Bastion Vault. Add a service name only when a corresponding
  # provision-*-frontend or platform-*-frontend consumer layer exists.
  _spire_operator_services = toset(["cilium", "harbor-origin", "vault"])

  # A service name absent from foundation-libvirt-resources, or missing a "frontend" component,
  # renders as null here instead of an opaque "Invalid index" crash in spire_terraform_operator_specs.
  _spire_operator_services_missing = [
    for s_name in local._spire_operator_services :
    s_name if try(local.state.metadata.global_topology_identity[s_name]["frontend"], null) == null
  ]

  # Keyed by cluster_name (project-service-component), derived from foundation-libvirt-resources
  # SSoT outputs. Adding a new consumer requires only adding its service name to the set above.
  spire_terraform_operator_specs = {
    for s_name in setsubtract(local._spire_operator_services, local._spire_operator_services_missing) :
    local.state.metadata.global_topology_identity[s_name]["frontend"].cluster_name => {
      jwt_role_name   = local.state.metadata.global_topology_identity[s_name]["frontend"].cluster_name
      kv_service_path = "secret/data/${local.state.metadata.global_credential_paths[s_name]["frontend"]}"
      # Matches the key convention of global_pki_map (service-component), independent of the
      # cluster_name (project-service-component) used by jwt_role_name. See the bastion_pki_leaf_roles
      # local in foundation-vault-bastion.
      pki_role_name = "${s_name}-frontend"
    }
  }
}

check "spire_operator_services_exist" {
  assert {
    condition     = length(local._spire_operator_services_missing) == 0
    error_message = "_spire_operator_services names foundation-libvirt-resources has no \"frontend\" component for: ${join(", ", local._spire_operator_services_missing)}."
  }
}
