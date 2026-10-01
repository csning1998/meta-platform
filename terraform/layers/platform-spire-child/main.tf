
# Multi-node control plane topology hosts co-located SPIRE server and agent control plane workloads.
module "platform_spire_child" {
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
  network_service_segments = []

  talos_iso_path           = local.talos_iso_path
  talos_version            = var.talos_version
  talos_kubernetes_version = var.talos_kubernetes_version
  cilium_inline_manifest   = data.helm_template.cilium.manifest

  allow_scheduling_on_control_planes = true
}

# Kubeconfig and TLS client credentials MUST be published to Vault KV for downstream automation.
module "credentials_spire_child" {
  source    = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version   = "0.1.1"
  providers = { vault = vault.bastion }

  vault_credential_context = {
    kv_namespace = dirname(dirname(local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["spire"]["child"].cluster_config))
    domain       = basename(dirname(local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["spire"]["child"].cluster_config))
    component    = basename(local.state.foundation_libvirt_resources.foundation_vault_path.kv_paths["spire"]["child"].cluster_config)
    static = {
      talos_ca_certificate_b64     = module.platform_spire_child.client_configuration.ca_certificate
      talos_client_certificate_b64 = module.platform_spire_child.client_configuration.client_certificate
      talos_client_key_b64         = module.platform_spire_child.client_configuration.client_key
      content_b64                  = base64encode(module.platform_spire_child.kubeconfig_raw)
    }
  }
}
