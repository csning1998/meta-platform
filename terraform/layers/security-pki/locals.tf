
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    bootstrapper         = data.terraform_remote_state.vault_bootstrapper.outputs
    production           = data.terraform_remote_state.vault_production.outputs
    vault_prod_bootstrap = data.terraform_remote_state.vault_prod_bootstrap.outputs
  }
}

locals {
  sys_vault_endpoint     = "https://${local.state.production.service_vip}:${local.state.production.vault_api_port}"
  bootstrap_ca_chain_pem = "${local.state.bootstrapper.bootstrap_root_ca_certificate_pem}\n${local.state.bootstrapper.bootstrap_intermediate_ca_certificate_pem}"
  pki_lease_ttl_seconds  = 60 * 60 * 24 * 365
  root_domain            = data.terraform_remote_state.foundation.outputs.global_domain_suffix
  vault_kv_namespace     = data.terraform_remote_state.foundation.outputs.vault_kv_namespace
}

locals {
  # Consolidated PKI roles: SSoT global_pki_map (machine workloads) merged with the
  # human management identities consumed by provision-vault-oidc and on-prem gitlab
  # for OIDC group-to-policy mapping.
  pki_roles = merge(
    {
      for key, item in data.terraform_remote_state.foundation.outputs.global_pki_map : key => {
        name            = item.role_name
        auth_method     = item.auth_config.method
        auth_path       = item.auth_config.path
        approle_path    = item.auth_config.approle_path
        allowed_domains = item.dns_san
        ou              = item.ou
        max_ttl         = 60 * 60 * 24 * 90
        ttl             = 60 * 60 * 24 * 30
      }
    },
    {
      "oidc-admin" = {
        name            = "oidc-admin"
        auth_method     = "approle"
        auth_path       = "workload-approle"
        approle_path    = "workload-approle"
        allowed_domains = [local.root_domain]
        ou              = ["infrastructure"]
        max_ttl         = 60 * 60 * 24 * 365
        ttl             = 60 * 60 * 24 * 30
      }
      "oidc-auditor" = {
        name            = "oidc-auditor"
        auth_method     = "approle"
        auth_path       = "workload-approle"
        approle_path    = "workload-approle"
        allowed_domains = [local.root_domain]
        ou              = ["compliance"]
        max_ttl         = 60 * 60 * 24 * 365
        ttl             = 60 * 60 * 24 * 30
      }
      "oidc-developer" = {
        name            = "oidc-developer"
        auth_method     = "approle"
        auth_path       = "workload-approle"
        approle_path    = "workload-approle"
        allowed_domains = [local.root_domain]
        ou              = ["development"]
        max_ttl         = 60 * 60 * 24 * 7
        ttl             = 60 * 60 * 24
      }
    }
  )

  management_identities = toset(["oidc-admin", "oidc-auditor", "oidc-developer"])

  # Extra ACL rules merged into each workload identity's generated policy, beyond the
  # baseline PKI issue capability. Only the human management identities need KV access here.
  workload_identity_extra_rules = {
    "oidc-admin" = {
      "secret/metadata/"                              = { capabilities = ["list"] }
      "secret/metadata/${local.vault_kv_namespace}/"  = { capabilities = ["list"] }
      "secret/data/${local.vault_kv_namespace}/*"     = { capabilities = ["create", "update", "read", "delete", "list"] }
      "secret/metadata/${local.vault_kv_namespace}/*" = { capabilities = ["list", "read", "delete"] }
      "auth/token/lookup-self"                        = { capabilities = ["read"] }
      "identity/lookup/entity"                        = { capabilities = ["read", "update"] }
    }
    "oidc-auditor" = {
      "secret/metadata/*"                         = { capabilities = ["list", "read"] }
      "secret/data/${local.vault_kv_namespace}/*" = { capabilities = ["read", "list"] }
      "sys/audit"                                 = { capabilities = ["read"] }
      "sys/policies/acl"                          = { capabilities = ["list", "read"] }
    }
    "oidc-developer" = {
      "secret/data/${local.vault_kv_namespace}/applications/*"     = { capabilities = ["create", "update", "read", "delete", "list"] }
      "secret/metadata/${local.vault_kv_namespace}/applications/*" = { capabilities = ["list", "read"] }
    }
  }
}
