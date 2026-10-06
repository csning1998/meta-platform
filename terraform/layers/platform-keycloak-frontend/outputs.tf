
output "node_exporter_targets" {
  description = "Node Exporter scrape target for the Keycloak node."
  value = {
    ips  = module.terraform_layer_context.svc_network.node_ips
    port = module.terraform_layer_context.node_exporter_port
  }
}
