
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    platform_spire_child              = data.terraform_remote_state.platform_spire_child.outputs
    platform_spire_parent             = data.terraform_remote_state.platform_spire_parent.outputs
    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    security_vault_downstream_pki     = data.terraform_remote_state.security_vault_downstream_pki.outputs
  }
}

locals {
  # The operator of the SPIRE Child logs in to the Downstream Vault with the JWT-SVID of the SPIRE Parent.
  downstream_operator = local.state.security_vault_downstream_tenants.component_operators["spire-child"]
  child_jwt_auth      = local.state.security_vault_downstream_tenants.child_jwt_auth

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
}

locals {
  ansible_config = {
    root_path         = abspath("${path.root}/../../../ansible")
    inventory_file    = "inventory-provision-spire-child.yaml"
    known_hosts_path  = local.state.platform_spire_child.foundation_ssh.known_hosts_paths[local.parent_cluster_name]
    identity_key_path = local.state.platform_spire_child.foundation_ssh.identity_key_paths[local.parent_cluster_name]
  }

  parent_cluster_name = local.topology.identity["spire"]["parent"].cluster_name

  # The registration on the SPIRE Parent runs over SSH. The operators of the workstation hold JWT-SVIDs of the SPIRE Parent
  # alone, hence the workstation does not run an agent of the SPIRE Child.
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
    }
  }

  # Execution variables contain non-sensitive coordinates. The runner retrieves secrets directly from the Downstream Vault.
  ansible_extra_vars = {
    operator_vault_ca_cert_path                    = local.state.security_vault_downstream_tenants.ca_cert_path
    operator_vault_url                             = local.state.security_vault_downstream_tenants.endpoint
    provision_spire_child_cluster_name             = local.cluster_name
    provision_spire_child_kubeconfig_vault_path    = local.kv_path.parent_attestor
    provision_spire_child_upstream_agent_alias     = local.spiffe_id.upstream_agent_alias
    provision_spire_child_server_spiffe_id         = local.spiffe_id.child_server
    provision_spire_child_upstream_agent_namespace = local.chart.system_namespace
    provision_spire_child_upstream_agent_sa        = local.chart.upstream_agent_sa
    provision_spire_child_server_namespace         = local.chart.server_namespace
    provision_spire_child_server_sa                = local.chart.internal_server_sa
    provision_spire_child_operator_wrapper         = local.downstream_operator.wrapper_name
    provision_spire_child_operator_role            = local.downstream_operator.role_name
    provision_spire_child_operator_auth_mount      = local.downstream_operator.auth_mount
  }
}
