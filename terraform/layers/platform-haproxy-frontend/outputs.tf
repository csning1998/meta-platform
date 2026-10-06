
output "runtime" {
  description = "Runtime of the component in the service catalog: the runtime name, and whether the runtime is Kubernetes native."
  value = {
    name              = local.haproxy_runtime
    kubernetes_native = contains(local.kubernetes_native_runtimes, local.haproxy_runtime)
  }
}

output "fronted_segments" {
  description = "Keys of the infrastructure_map segments this tier fronts, for cross-checking against provision-cilium-hubble's own exclusion list."
  value       = keys(local.fronted_segments)
}

output "node_exporter_targets" {
  description = "Node Exporter scrape targets (per-node IPs and port) for the HAProxy VM fleet."
  value = {
    ips  = module.terraform_layer_context.cluster_network.node_ips
    port = module.terraform_layer_context.node_exporter_port
  }
}
