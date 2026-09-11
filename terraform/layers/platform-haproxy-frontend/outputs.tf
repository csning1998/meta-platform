
output "fronted_segments" {
  description = "Keys of the infrastructure_map segments this tier fronts, for cross-checking against provision-cilium-frontend's own exclusion list."
  value       = keys(local.fronted_segments)
}

output "node_exporter_targets" {
  description = "Node Exporter scrape targets (per-node IPs and port) for the HAProxy VM fleet."
  value = {
    ips  = module.context.svc_network.node_ips
    port = module.context.node_exporter_port
  }
}
