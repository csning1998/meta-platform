
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    security_vault_downstream_pki     = data.terraform_remote_state.security_vault_downstream_pki.outputs
    platform_keycloak_frontend        = data.terraform_remote_state.platform_keycloak_frontend.outputs
    foundation_libvirt_resources      = data.terraform_remote_state.foundation_libvirt_resources.outputs
  }
}

locals {
  fdqn = {
    keycloak_frontend = local.state.security_vault_downstream_tenants.foundation_pki.map["keycloak-frontend"].dns_san[0]
    vault_frontend    = local.state.security_vault_downstream_tenants.foundation_pki.map["vault-downstream-frontend"].dns_san[0]
  }
}

locals {
  all_group_ids = merge(
    { for k, v in keycloak_group.root_groups : k => v.id },
    { for k, v in keycloak_group.subgroups : k => v.id }
  )
}

locals {
  # Downstream OIDC clients derived from global_pki_map: declaring oidc_client on a
  # component in service_catalog is sufficient to onboard a new consumer here.
  downstream_oidc_clients_resolved = {
    for k, v in local.state.security_vault_downstream_tenants.foundation_pki.map : k => {
      client_id           = v.oidc_client.client_id
      name                = v.oidc_client.name
      valid_redirect_uris = ["https://${v.dns_san[0]}${v.oidc_client.redirect_path}"]
      web_origin          = "https://${v.dns_san[0]}"
    }
    if v.oidc_client != null
  }
}

locals {
  # Endpoint Construction
  keycloak_frontend_url = "https://${local.fdqn.keycloak_frontend}"
  vault_frontend_url    = "https://${local.fdqn.vault_frontend}"

  # Admin Credentials
  keycloak_admin_user     = ephemeral.vault_kv_secret_v2.keycloak_admin.data["keycloak_admin_user"]
  keycloak_admin_password = ephemeral.vault_kv_secret_v2.keycloak_admin.data["keycloak_admin_password"]

  # OIDC Configuration Constants
  realm_id = "infra-company"

  # Centralized Redirect URIs for Vault
  vault_redirect_uris = [
    "${local.vault_frontend_url}/ui/vault/auth/oidc/oidc/callback",
    "${local.vault_frontend_url}/ui/vault/auth/oidc/callback",
    "${local.vault_frontend_url}/vault/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]
}

locals {
  kv_paths = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths
}

# The Talos runtime of Keycloak carries an in-cluster cert-manager and External Secrets Operator, which log in to the Downstream Vault.
locals {
  is_runtime_talos = contains(
    local.state.foundation_libvirt_resources.foundation_topology.kubernetes_native_runtimes,
    local.state.platform_keycloak_frontend.runtime
  )

  cluster_issuer   = local.state.platform_keycloak_frontend.cluster_issuer
  external_secrets = local.state.platform_keycloak_frontend.external_secrets

  cluster_name = local.state.foundation_libvirt_resources.foundation_topology.identity["keycloak"]["frontend"].cluster_name
  cluster_vip  = local.state.foundation_libvirt_resources.foundation_topology.infrastructure[local.cluster_name].lb_config.vip

  downstream_vault = {
    address = local.state.security_vault_downstream_tenants.endpoint
    ca_cert = file(local.state.security_vault_downstream_tenants.ca_cert_path)
  }
}

locals {
  kubeconfig = local.is_runtime_talos ? yamldecode(base64decode(ephemeral.vault_kv_secret_v2.keycloak_cluster[0].data["content_b64"])) : null

  api_server_connection = local.is_runtime_talos ? {
    host               = local.kubeconfig.clusters[0].cluster.server
    ca_cert            = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
    client_certificate = base64decode(local.kubeconfig.users[0].user["client-certificate-data"])
    client_key         = base64decode(local.kubeconfig.users[0].user["client-key-data"])
    } : {
    host               = null
    ca_cert            = null
    client_certificate = null
    client_key         = null
  }

  # The token reviewer authenticates to the API server on its own, with the VIP of the cluster and its root CA.
  api_server_callback = local.is_runtime_talos ? {
    host    = "https://${local.cluster_vip}:6443"
    ca_cert = data.kubernetes_config_map_v1.root_ca[0].data["ca.crt"]
  } : null
}

# The operator of this component logs in to the Downstream Vault with the JWT-SVID of the SPIRE Parent.
locals {
  downstream_operator = local.state.security_vault_downstream_tenants.component_operators["keycloak"]
}
