
output "service_vip" {
  description = "The virtual IP assigned to the Vault service from Central LB topology."
  value       = module.context.primary_net_config.lb_config.vip
}

output "ca_cert_path" {
  description = "The absolute path to the local Bootstrap CA certificate."
  value       = abspath(local_file.bootstrap_ca.filename)
}

output "api_port" {
  description = "Vault API frontend port for provision-* tier consumption."
  value       = module.context.primary_net_config.lb_config.ports["api"].frontend_port
}

output "endpoint" {
  description = "Downstream Vault API endpoint URL which every consumer layer reads instead of rebuilding the address."
  value       = "https://${module.context.primary_net_config.lb_config.vip}:${module.context.primary_net_config.lb_config.ports["api"].frontend_port}"
}

output "node_exporter_targets" {
  description = "Node Exporter scrape targets (per-node IPs and port) for the Vault frontend VM fleet."
  value = {
    ips  = module.context.svc_network.node_ips
    port = module.context.node_exporter_port
  }
}

output "pki_identity" {
  description = "Identity of the intermediate CA which the Downstream Vault holds, for the layers which create the PKI engine and its policies."
  value       = var.pki_identity
}
