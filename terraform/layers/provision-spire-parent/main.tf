
# Federated workload identity mint point establishing short-lived Vault access via SPIRE JWT-SVID attestation.
module "spire_terraform_operator" {
  source   = "../../modules/vault-provisioning/vault-spiffe-workload-identity-federation"
  for_each = local.spire_terraform_operator_specs

  auth_role_name    = each.key
  pki_role_name     = each.value.cluster_name
  auth_backend_path = local.state.platform_spire_parent.spire_oidc_auth_backend_path
  pki_mount_path    = local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_mount_path
  spiffe_id         = "spiffe://${local.state.platform_spire_parent.spire_agent_bootstrap.trust_domain}${each.value.spiffe_path}"
  token_ttl         = var.spire_terraform_operator_token.ttl
  token_max_ttl     = var.spire_terraform_operator_token.max_ttl

  extra_policy_paths = merge(
    {
      # auth/*
      # Grants cluster-scoped authority for workload identity lifecycle and bootstrap PKI leaf issuance.
      "auth/${local.state.platform_spire_parent.spire_oidc_auth_backend_path}/role/${each.value.cluster_name}" = {
        capabilities = ["create", "read", "update", "delete"]
      }

      # secret/*
      # The registrar credential of the SPIRE Child grants exec into the pod of the Child server only.
      # The exact path outranks the glob of the component, and the operator of the Child which writes the credential keeps its write grant.
      "secret/data/${local.kv_paths["spire"]["child"].registrar}" = {
        capabilities = each.value.output_key == "spire-child" ? ["create", "read", "update", "delete", "patch"] : ["read"]
      }
      "secret/data/parent-group-governance/terraform/state-backend" = { capabilities = ["read"] }

      # sys/*
      "sys/internal/ui/mounts/secret/*"                                                              = { capabilities = ["read"] }
      "sys/mounts/${local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_mount_path}" = { capabilities = ["read"] }
      "sys/policies/acl/${each.value.cluster_name}" = {
        capabilities = ["create", "read", "update", "delete"]
      }
      "sys/policies/acl/${each.value.cluster_name}-*" = {
        capabilities = ["create", "read", "update", "delete"]
      }

      # Delegates administration of the auth mounts and their contents within the cluster-scoped prefix.
      "sys/auth/${each.value.cluster_name}-*" = {
        capabilities = ["create", "read", "update", "delete", "sudo"]
      }
      "sys/mounts/auth/${each.value.cluster_name}-*" = {
        capabilities = ["create", "read", "update"]
      }
      "auth/${each.value.cluster_name}-*" = {
        capabilities = ["create", "read", "update", "delete", "list"]
      }

      # ${bastion_vault_pki.intermediate_mount_path}/*
      "${local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_mount_path}/roles/${each.value.cluster_name}" = {
        capabilities = ["create", "read", "update", "delete"]
      }
      "${local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_mount_path}/issue/${each.value.cluster_name}" = {
        capabilities = ["create", "update"]
      }
    },
    {
      # Grants the leaves below the component folder, such as credentials minted by later layers.
      # The SSH identity leaf belongs to security-vault-bastion-credentials, and the exact rule outranks the glob.
      "${each.value.kv_service_path}/*" = { capabilities = ["create", "read", "update", "delete", "patch"] }
      "${replace(each.value.kv_service_path, "secret/data/", "secret/metadata/")}" = {
        capabilities = ["list"]
      }
      "${replace(each.value.kv_service_path, "secret/data/", "secret/metadata/")}/*" = {
        capabilities = ["create", "read", "update", "list", "delete"]
      }
      "${each.value.kv_service_path}/${local.kv_leaf_ssh}"                                              = { capabilities = ["deny"] }
      "${replace(each.value.kv_service_path, "secret/data/", "secret/metadata/")}/${local.kv_leaf_ssh}" = { capabilities = ["deny"] }
    },
    # The operator of the Downstream Vault has its Issuing Intermediate signed at the Bastion Vault.
    each.value.output_key == "vault-downstream" ? {
      "${local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_mount_path}/root/sign-intermediate" = { capabilities = ["create", "update"] }
    } : {},
    # Scopes SPIRE agent join-token storage to the nodes of the target consumer cluster, below the server which issues the token.
    merge([
      for server in ["parent", "child"] : {
        for cluster in concat([each.value.cluster_name], each.value.output_key == "spire-child" && server == "child" ? [local.workstation_cluster_name] : []) :
        "secret/data/${local.kv_paths["spire"][server].join_token}/${cluster}/*" => { capabilities = ["create", "read", "update"] }
      }
    ]...),
    merge([
      for server in ["parent", "child"] : {
        for cluster in concat([each.value.cluster_name], each.value.output_key == "spire-child" && server == "child" ? [local.workstation_cluster_name] : []) :
        "secret/metadata/${local.kv_paths["spire"][server].join_token}/${cluster}/*" => { capabilities = ["create", "read", "update", "list"] }
      }
    ]...)
  )
}

module "ansible_operator_identity" {
  source     = "../../modules/kvm-provisioning/cluster-provision/ansible-runner"
  depends_on = [module.spire_terraform_operator]

  status_trigger = local.spire_terraform_operator_specs
  ansible_config = local.ansible_config
  inventory_data = local.inventory_data
  extra_vars     = local.ansible_extra_vars
  ansible_tags   = ["spire_agent", "terraform_operator_identity", "terraform_operator_verify"]
  playbook_paths = [
    "${local.ansible_config.root_path}/playbooks/playbook_host_terraform_operator.yaml"
  ]
}
