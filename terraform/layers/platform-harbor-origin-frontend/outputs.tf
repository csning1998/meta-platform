
output "harbor_endpoint" {
  description = "Connection and endpoint facts for Harbor Origin."
  value = {
    fqdn        = module.terraform_layer_context.cluster_fqdn
    listen_ip   = local.harbor_listen_ip
    service_vip = module.terraform_layer_context.primary_network_config.lb_config.vip
    pki_key     = module.terraform_layer_context.primary_context.pki_key
  }
}

output "generic_cluster" {
  description = "Facts of the Harbor Origin VM cluster."
  value = {
    topology_node        = module.establish_platform_harbor_origin_generic_cluster.cluster_nodes
    ansible_inventory    = module.establish_platform_harbor_origin_generic_cluster.ansible_inventory
    ssh_config_file_path = module.establish_platform_harbor_origin_generic_cluster.ssh_config_file_path
    node_exporter_targets = {
      ips  = module.terraform_layer_context.cluster_network.node_ips
      port = module.terraform_layer_context.node_exporter_port
    }
  }
}
