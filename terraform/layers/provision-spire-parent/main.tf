
# Generic mint point for every entry in local.spire_terraform_operator_specs. Trust source is a
# SPIRE-issued SVID, fetched as a JWT-SVID by the wrapper script of the utils_terraform_operator_identity
# role and attested through the unix WorkloadAttestor of the SPIRE Agent on this host.
module "spire_terraform_operator" {
  source   = "../../modules/vault-provisioning/vault-spiffe-workload-identity-federation"
  for_each = local.spire_terraform_operator_specs

  auth_role_name    = each.key
  pki_role_name     = each.value.cluster_name
  auth_backend_path = local.state.spire_parent.spire_oidc_auth_backend_path
  pki_mount_path    = local.state.vault_bastion.bastion_vault_pki.intermediate_mount_path
  spiffe_id         = "spiffe://${local.state.spire_parent.spire_agent_bootstrap.trust_domain}${each.value.spiffe_path}"
  token_ttl         = var.spire_terraform_operator_token.ttl
  token_max_ttl     = var.spire_terraform_operator_token.max_ttl

  extra_policy_paths = merge(
    {
      # auth/*
      # Provisions the consumer own workload identity, whose role and policy names equal its cluster_name,
      # plus the PKI leaf cert which the workload identity issues at bootstrap.
      "auth/${local.state.spire_parent.spire_oidc_auth_backend_path}/role/${each.value.cluster_name}" = {
        capabilities = ["create", "read", "update", "delete"]
      }

      # secret/*
      "secret/data/meta-platform/guest_vm"                          = { capabilities = ["read"] }
      "secret/data/parent-group-governance/terraform/state-backend" = { capabilities = ["read"] }

      # sys/*
      "sys/internal/ui/mounts/secret/*"                                                   = { capabilities = ["read"] }
      "sys/mounts/${local.state.vault_bastion.bastion_vault_pki.intermediate_mount_path}" = { capabilities = ["read"] }
      "sys/policies/acl/${each.value.cluster_name}" = {
        capabilities = ["create", "read", "update", "delete"]
      }

      # ${bastion_vault_pki.intermediate_mount_path}/*
      "${local.state.vault_bastion.bastion_vault_pki.intermediate_mount_path}/issue/${each.value.cluster_name}" = {
        capabilities = ["create", "update"]
      }
    },
    {
      "${each.value.kv_service_path}" = { capabilities = ["create", "read", "update", "delete", "patch"] }
      "${replace(each.value.kv_service_path, "secret/data/", "secret/metadata/")}" = {
        capabilities = ["read", "list", "delete"]
      }
    }
  )
}

module "ansible_operator_identity" {
  source = "../../modules/kvm-provisioning/cluster-provision/ansible-runner"

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
