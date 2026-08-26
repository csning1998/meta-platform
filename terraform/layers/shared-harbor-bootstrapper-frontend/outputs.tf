
output "harbor_origin_fqdn" {
  description = "The FQDN of the Bootstrap Harbor service."
  value       = module.context.svc_fqdn
}

output "listen_ip" {
  description = "Node IP used to reach Harbor before Cilium announces the catalog VIP."
  value       = local.harbor_listen_ip
}

output "service_vip" {
  description = "Catalog VIP reserved for Harbor. Sequence 3 announces this address. Sequence 2 does not publish it."
  value       = module.context.primary_net_config.lb_config.vip
}

output "topology_node" {
  description = "The actual provisioned configuration for Bootstrap Harbor node."
  value       = module.infra_harbor_origin.cluster_nodes
}

output "pki_key" {
  description = "The physical SSoT PKI key associated with the Harbor Bootstrapper service."
  value       = module.context.primary_context.pki_key
}

output "ansible_inventory" {
  description = "The generated Ansible inventory content and file path."
  value       = module.infra_harbor_origin.ansible_inventory
}

output "ssh_config_file_path" {
  description = "The path to the generated SSH configuration file."
  value       = module.infra_harbor_origin.ssh_config_file_path
}

output "node_exporter_targets" {
  description = "Node Exporter scrape target for the Harbor Bootstrapper node."
  value = {
    ips  = module.context.svc_network.node_ips
    port = module.context.node_exporter_port
  }
}
