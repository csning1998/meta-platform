
module "platform_cilium_frontend" {
  source = "../../modules/kvm-provisioning/ha-service-kvm-talos-lb"

  svc_identity = merge(local.svc_identity, {
    service_name  = local.svc_cluster_name
    domain_suffix = local.svc_fqdn
  })

  topology_cluster = {
    storage_pool_name = local.svc_identity.storage_pool_name

    load_balancer_config = {
      nodes = {
        for key, spec in var.node_config : local.net_node_naming_map[key] => spec
      }
    }
  }

  svc_network_map = local.network_map

  network_infrastructure_map = {
    (local.svc_cluster_name) = local.net_lb_config
  }
  network_service_segments = local.net_service_segments

  talos_iso_path           = local.talos_iso_path
  talos_version            = var.talos_version
  talos_kubernetes_version = var.talos_kubernetes_version
  cilium_inline_manifest   = data.helm_template.cilium.manifest
}

# The kubeconfig belongs to the cluster lifecycle, so this layer writes it to the Bastion Vault itself.
module "credentials_cilium_frontend" {
  source    = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version   = "0.1.1"
  providers = { vault = vault }

  vault_credential_context = {
    kv_namespace = local.vault_kv_namespace
    domain       = "cilium"
    component    = "frontend"
    static = {
      talos_ca_certificate_b64     = module.platform_cilium_frontend.client_configuration.ca_certificate
      talos_client_certificate_b64 = module.platform_cilium_frontend.client_configuration.client_certificate
      talos_client_key_b64         = module.platform_cilium_frontend.client_configuration.client_key
      content_b64                  = base64encode(module.platform_cilium_frontend.kubeconfig_raw)
    }
  }
}
