
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  state = {
    platform_spire_child     = data.terraform_remote_state.platform_spire_child.outputs
    foundation_vault_bastion = data.terraform_remote_state.foundation_vault_bastion.outputs
    platform_spire_parent    = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_parent   = data.terraform_remote_state.provision_spire_parent.outputs
  }
}

locals {
  terraform_operator = local.state.provision_spire_parent.terraform_operator["spire-child"]

  topology = local.state.platform_spire_child.foundation_topology
  identity = local.topology.identity["spire"]["child"]
  network  = local.topology.network["spire"]["child"]

  project_code = local.state.platform_spire_child.foundation_vault_path.project_code
  cluster_name = local.identity.cluster_name

  kv_path = {
    cluster         = local.state.platform_spire_child.foundation_vault_path.kv_paths["spire"]["child"].cluster_config
    parent_attestor = local.state.platform_spire_child.foundation_vault_path.kv_paths["spire"]["child"].parent_attestor
    registrar       = local.state.platform_spire_child.foundation_vault_path.kv_paths["spire"]["child"].registrar
  }
}

locals {
  kubeconfig   = yamldecode(base64decode(ephemeral.vault_kv_secret_v2.spire_child.data["content_b64"]))
  cluster_info = local.kubeconfig.clusters[0].cluster
  user_info    = local.kubeconfig.users[0].user

  api_server_connection = {
    host               = local.cluster_info.server
    ca_cert            = base64decode(local.cluster_info["certificate-authority-data"])
    client_certificate = base64decode(local.user_info["client-certificate-data"])
    client_key         = base64decode(local.user_info["client-key-data"])
  }

  # SPIRE parent interacts with the child Kubernetes API server via the control plane VIP.
  api_server_vip_url = "https://${local.network.vip}:6443"
}

# SPIRE parent and nested child share a unified SPIFFE trust domain across VM and container boundaries.
locals {
  parent = local.state.platform_spire_parent.spire_agent_bootstrap

  trust_domain = local.parent.trust_domain

  spiffe_id = {
    # Downstream child SPIRE server workload identity.
    child_server = "spiffe://${local.trust_domain}/${local.project_code}/spire/child"
    # Upstream agent node alias grouping containerized agents under parent trust domain.
    upstream_agent_alias = "spiffe://${local.trust_domain}/${local.project_code}/spire/child/upstream-agent"
  }

  # Chart-standard namespace and service account names aligned with parent k8s_psat attestation allow-lists.
  chart = {
    system_namespace        = "spire-system"
    server_namespace        = "spire-server"
    upstream_agent_sa       = "spire-agent-upstream"
    internal_server_sa      = "spire-internal-server"
    internal_server_service = "spire-internal-server"
    internal_server_pod     = "spire-internal-server-0"
    registrar_sa            = "spire-child-registrar"
    upstream_bundle_cm      = "spire-bundle-upstream"
    oidc_service_name       = "spiffe-oidc-discovery-provider"
    oidc_tls_secret         = "spiffe-oidc-discovery-provider-tls"
    parent_attestor_sa      = "spire-parent-attestor"
    parent_attestor_rbac    = "spire-parent-attestor"
    upstream_bundle_field   = "bundle.crt"
  }

  # OIDC discovery provider allocates the static VIP immediately following the control plane VIP.
  oidc_vip = cidrhost(local.network.cidr_block, local.state.platform_spire_child.foundation_global.network_baseline.host_vip_offset + 1)

  # The agents of the downstream VMs and of the operator workstation attest to the child server through this static VIP.
  agent_vip  = cidrhost(local.network.cidr_block, local.state.platform_spire_child.foundation_global.network_baseline.host_vip_offset + 2)
  agent_port = 443
  jwt_issuer = "https://${local.oidc_vip}"

  # Downstream Vault mounts dedicated JWT-SVID auth backend scoped strictly to child SPIRE workload tokens.
  jwt_svid_auth_mount_path = "${local.cluster_name}-jwt-svid-provider"
}

locals {
  ansible_config = {
    root_path         = abspath("${path.root}/../../../ansible")
    inventory_file    = "inventory-provision-spire-child.yaml"
    known_hosts_path  = local.state.platform_spire_child.foundation_ssh.known_hosts_paths[local.parent_cluster_name]
    identity_key_path = local.state.platform_spire_child.foundation_ssh.identity_key_paths[local.parent_cluster_name]
  }

  parent_cluster_name = local.topology.identity["spire"]["parent"].cluster_name

  # Both runner modules of the layer write this inventory, the same configuration, and the same trigger, since the
  # modules share one ansible.cfg. The plays select their hosts by group. The registration on the SPIRE Parent runs over
  # SSH, and the agent of the operator workstation runs locally.
  inventory_data = {
    all = {
      children = {
        spire_child_registration = {
          hosts = {
            (local.parent.ssh_host) = {
              ansible_host = local.parent.ssh_host
            }
          }
        }
      }
      hosts = {
        "host-terraform-operator-workstation" = {
          ansible_connection         = "local"
          ansible_python_interpreter = "/usr/bin/python3"
          node_role                  = "host_terraform_operator"
          spire_cluster_name         = "host-terraform-operator"
          spire_trust_domain         = local.trust_domain
        }
      }
    }
  }

  # The Terraform operator identities which the Child registers for the login to the Downstream Vault.
  terraform_operators = local.state.provision_spire_parent.terraform_operator
  downstream_audience = local.topology.identity["vault-downstream"]["frontend"].cluster_name

  # Execution variables contain non-sensitive coordinates. The runner retrieves secrets directly from Vault.
  ansible_extra_vars = {
    bastion_vault_ca_cert_path                     = local.state.foundation_vault_bastion.bastion_vault.listener_ca_cert_path
    bastion_vault_endpoint                         = local.state.foundation_vault_bastion.bastion_vault.endpoint
    provision_spire_child_cluster_name             = local.cluster_name
    provision_spire_child_kubeconfig_vault_path    = local.kv_path.parent_attestor
    provision_spire_child_upstream_agent_alias     = local.spiffe_id.upstream_agent_alias
    provision_spire_child_server_spiffe_id         = local.spiffe_id.child_server
    provision_spire_child_upstream_agent_namespace = local.chart.system_namespace
    provision_spire_child_upstream_agent_sa        = local.chart.upstream_agent_sa
    provision_spire_child_server_namespace         = local.chart.server_namespace
    provision_spire_child_server_sa                = local.chart.internal_server_sa
    provision_spire_child_operator_wrapper         = local.terraform_operator.wrapper_name
    provision_spire_child_operator_role            = local.terraform_operator.role_name
    provision_spire_child_operator_auth_mount      = local.state.platform_spire_parent.spire_oidc_auth_backend_path

    # The plays of the operator workstation.
    bastion_operator_wrapper                       = local.terraform_operator.wrapper_name
    bastion_operator_role                          = local.terraform_operator.role_name
    bastion_operator_auth_mount                    = local.state.platform_spire_parent.spire_oidc_auth_backend_path
    spire_child_agent_address                      = local.agent_vip
    spire_child_agent_port                         = tostring(local.agent_port)
    spire_child_kubeconfig_kv_path                 = local.kv_path.registrar
    spire_parent_join_token_kv_path                = local.state.platform_spire_child.foundation_vault_path.kv_paths["spire"]["parent"].join_token
    spire_child_join_token_kv_path                 = local.state.platform_spire_child.foundation_vault_path.kv_paths["spire"]["child"].join_token
    spire_child_jwt_audience                       = local.downstream_audience
    utils_terraform_operator_identity_names        = jsonencode([for key, op in local.terraform_operators : op.role_name])
    utils_terraform_operator_identity_spiffe_paths = jsonencode({ for key, op in local.terraform_operators : op.role_name => op.spiffe_path })
  }
}
