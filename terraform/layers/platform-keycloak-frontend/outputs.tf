
output "runtime" {
  description = "Runtime of the Keycloak component in the service catalog: the runtime name, and whether the runtime is Kubernetes native, which selects talos_cluster or generic_cluster."
  value = {
    name              = local.keycloak_cluster_runtime
    kubernetes_native = local.is_runtime_talos
  }
}

output "keycloak_endpoint" {
  description = "Connection and endpoint facts of the Keycloak service."
  value = {
    fqdn        = module.terraform_layer_context.cluster_fqdn
    service_vip = module.terraform_layer_context.primary_network_config.lb_config.vip
    pki_key     = module.terraform_layer_context.primary_context.pki_key
  }
}

output "talos_cluster" {
  description = "Facts of the Talos runtime, with null fields on the VM runtime."
  value = {
    enabled            = local.is_runtime_talos
    hostonly_addresses = one(module.establish_platform_keycloak_talos_cluster[*].hostonly_addresses)
    bootstrap_node_key = one(module.establish_platform_keycloak_talos_cluster[*].bootstrap_node_key)
    volume_mount_path  = one(module.establish_platform_keycloak_talos_cluster[*].volume_mount_path)
    cluster_issuer     = one(module.vault_auth_keycloak_talos[*].cluster_issuer)
    external_secrets   = one(module.vault_auth_keycloak_talos[*].external_secrets)
  }
}

output "generic_cluster" {
  description = "Facts of the VM runtime, with null fields on the Talos runtime."
  value = {
    enabled              = !local.is_runtime_talos
    topology_node        = one(module.establish_platform_keycloak_generic_cluster[*].cluster_nodes)
    ssh_config_file_path = one(module.establish_platform_keycloak_generic_cluster[*].ssh_config_file_path)
    node_exporter_targets = local.is_runtime_talos ? null : {
      ips  = module.terraform_layer_context.cluster_network.node_ips
      port = module.terraform_layer_context.node_exporter_port
    }
  }
}
