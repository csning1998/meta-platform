
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  state = {
    foundation_vault_bastion           = data.terraform_remote_state.foundation_vault_bastion.outputs
    platform_vault_downstream_frontend = data.terraform_remote_state.platform_vault_downstream_frontend.outputs
    security_vault_downstream_tenants  = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    foundation_libvirt_resources       = data.terraform_remote_state.foundation_libvirt_resources.outputs
    platform_spire_parent              = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_parent             = data.terraform_remote_state.provision_spire_parent.outputs
    provision_spire_child              = data.terraform_remote_state.provision_spire_child.outputs
  }
  project_code = local.state.foundation_libvirt_resources.foundation_vault_path.project_code
}

locals {
  downstream_vault = {
    endpoint       = local.state.platform_vault_downstream_frontend.endpoint
    pki_mount_path = local.state.platform_vault_downstream_frontend.pki_identity.intermediate_mount_path
  }
  pki_lease_ttl_seconds = 60 * 60 * 24 * 365
  bastion_pki_chain_pem = "${local.state.foundation_vault_bastion.bastion_vault_pki.root_cert_pem}\n${local.state.foundation_vault_bastion.bastion_vault_pki.intermediate_cert_pem}"
  root_domain           = local.state.foundation_libvirt_resources.foundation_global.domain_suffix
}

locals {
  # Machine workloads which take their listener certificate from the Downstream Vault. The other services obtain a
  # certificate from the Bastion PKI role which their own platform layer creates, and need no role here.
  downstream_pki_services = toset(["keycloak-frontend", "harbor-origin-frontend"])

  # Consolidated PKI roles: the machine workloads above merged with the human management identities
  # consumed by provision-vault-oidc and on-prem gitlab for OIDC group-to-policy mapping.
  # The role name equals the identity string of the workload, which is the owner code followed by the catalog key.
  pki_roles = merge(
    {
      for key, item in local.state.foundation_libvirt_resources.foundation_pki.map : key => {
        name            = "${local.project_code}-${key}"
        auth_method     = item.auth_config.method
        auth_path       = item.auth_config.path
        allowed_domains = item.dns_san
        ou              = item.ou
        max_ttl         = 60 * 60 * 24 * 90
        ttl             = 60 * 60 * 24 * 30
      }
      if contains(local.downstream_pki_services, key)
    },
    {
      "oidc-admin" = {
        name            = "oidc-admin"
        auth_method     = "oidc"
        auth_path       = "oidc"
        allowed_domains = [local.root_domain]
        ou              = ["infrastructure"]
        max_ttl         = 60 * 60 * 24 * 365
        ttl             = 60 * 60 * 24 * 30
      }
      "oidc-auditor" = {
        name            = "oidc-auditor"
        auth_method     = "oidc"
        auth_path       = "oidc"
        allowed_domains = [local.root_domain]
        ou              = ["compliance"]
        max_ttl         = 60 * 60 * 24 * 365
        ttl             = 60 * 60 * 24 * 30
      }
      "oidc-developer" = {
        name            = "oidc-developer"
        auth_method     = "oidc"
        auth_path       = "oidc"
        allowed_domains = [local.root_domain]
        ou              = ["development"]
        max_ttl         = 60 * 60 * 24 * 7
        ttl             = 60 * 60 * 24
      }
    }
  )

  management_identities = toset(["oidc-admin", "oidc-auditor", "oidc-developer"])

  # Extra ACL rules merged into each workload identity's generated policy, beyond the
  # baseline PKI issue capability.
  workload_identity_extra_rules = {
    "oidc-admin" = {
      "secret/metadata/"                        = { capabilities = ["list"] }
      "secret/metadata/${local.project_code}/"  = { capabilities = ["list"] }
      "secret/data/${local.project_code}/*"     = { capabilities = ["create", "update", "read", "delete", "list"] }
      "secret/metadata/${local.project_code}/*" = { capabilities = ["list", "read", "delete"] }
      "auth/token/lookup-self"                  = { capabilities = ["read"] }
      "identity/lookup/entity"                  = { capabilities = ["read", "update"] }
    }
    "oidc-auditor" = {
      "secret/metadata/*"                   = { capabilities = ["list", "read"] }
      "secret/data/${local.project_code}/*" = { capabilities = ["read", "list"] }
      "sys/audit"                           = { capabilities = ["read"] }
      "sys/policies/acl"                    = { capabilities = ["list", "read"] }
    }
    "oidc-developer" = {
      "secret/data/${local.project_code}/applications/*"     = { capabilities = ["create", "update", "read", "delete", "list"] }
      "secret/metadata/${local.project_code}/applications/*" = { capabilities = ["list", "read"] }
    }
  }
}
