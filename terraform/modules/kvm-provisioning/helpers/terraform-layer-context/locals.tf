
locals {
  segments_map = merge([
    for s_name, components in var.global_topology_identity : {
      for c_name, identity in components : identity.cluster_name => {
        identity = identity
        network  = var.global_topology_network[s_name][c_name]
        pki_key  = "${s_name}-${c_name}"
        s_name   = s_name
        c_name   = c_name
      }
    }
  ]...)

  components_context = {
    for role, cluster_name in var.target_clusters : role => local.segments_map[cluster_name]
  }

  primary_context = local.components_context[var.primary_role]

  svc_identity = local.primary_context.identity
  svc_network  = local.primary_context.network
  svc_pki_role = var.global_pki_map[local.primary_context.pki_key]
  svc_fqdn     = local.svc_pki_role.dns_san[0]
}

# Deduplicates tier parameters by taking index [0], which is safe because roles sharing a tier resolve to the same cluster.
locals {
  network_infrastructure_map_grouped = {
    for role, ctx in local.components_context :
    var.service_config[role].network_tier => var.infrastructure_map[ctx.identity.cluster_name]...
  }

  network_infrastructure_map = {
    for k, v in local.network_infrastructure_map_grouped : k => v[0]
  }

  primary_net_config = local.network_infrastructure_map[var.service_config[var.primary_role].network_tier]

  # Full global_topology_network entry per network_tier, exposing ports (frontend and backend)
  # and node_ips for downstream layers that need non-LB topology data such as metrics endpoints.
  # The ...[0] grouping mirrors network_infrastructure_map. duplicate tiers always resolve to the same cluster.
  tier_network_map_grouped = {
    for role, ctx in local.components_context :
    var.service_config[role].network_tier => ctx.network...
  }

  tier_network_map = {
    for k, v in local.tier_network_map_grouped : k => v[0]
  }
}

locals {
  prod_vault_endpoint = var.prod_vault_svc_vip != null ? "https://${var.prod_vault_svc_vip}:443" : null

  # A cluster without SSH, such as a Talos cluster, does not carry a guest username.
  sec_vm_credentials = {
    username = lookup(var.guest_usernames, local.svc_identity.cluster_name, null)
  }
}

locals {
  storage_pool_name = local.svc_identity.storage_pool_name

  topology_cluster = {
    components        = var.service_config
    storage_pool_name = local.storage_pool_name
  }

  node_identities = {
    for role, ctx in local.components_context : role => ctx.identity
  }
}

# Constructs partial Vault Agent identity maps augmented downstream with tenant JWT credentials.
locals {
  all_vault_agent_identity_bases = var.security_pki_outputs != null ? {
    for role, ctx in local.components_context : role => {
      vault_endpoint = local.prod_vault_endpoint
      role_name      = var.security_pki_outputs.prod_pki_configuration.leaf_roles[var.global_pki_map[ctx.pki_key].key].name
      ca_cert_b64    = var.security_pki_outputs.bastion_pki_chain_b64.content_b64
      issuer_ca_b64  = var.security_pki_outputs.prod_pki_issuer_cert_b64
      common_name    = var.global_pki_map[ctx.pki_key].dns_san[0]
      pki_mount_path = var.security_pki_outputs.prod_pki_configuration.path
    }
  } : {}

  vault_agent_identity_base = lookup(local.all_vault_agent_identity_bases, var.primary_role, null)
}
