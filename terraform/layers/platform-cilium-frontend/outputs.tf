
output "infrastructure_vips" {
  description = "Aggregated list of all internal service VIPs requiring static route overrides."
  value       = local.infrastructure_vips
}

output "foundation_topology" {
  description = "Pass-through of the foundation-libvirt-resources topology object."
  value       = local.state.network.foundation_topology
}

output "foundation_global" {
  description = "Pass-through of the foundation-libvirt-resources global facts object."
  value       = local.state.network.foundation_global
}

output "hostonly_addresses" {
  description = "Static HostOnly interface addresses per Talos node."
  value       = module.platform_cilium_frontend.hostonly_addresses
}

output "bootstrap_node_key" {
  description = "The node key used as the etcd bootstrap and Kubernetes API endpoint target."
  value       = module.platform_cilium_frontend.bootstrap_node_key
}
