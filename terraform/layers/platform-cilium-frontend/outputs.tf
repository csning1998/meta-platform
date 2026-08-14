
output "infrastructure_map" {
  description = "Physical realization bridging foundation-libvirt-resources topology and Central LB VIPs, mapped to O(1) SSoT Identity keys."
  value       = data.terraform_remote_state.network.outputs.infrastructure_map
}

output "infrastructure_vips" {
  description = "Aggregated list of all internal service VIPs requiring static route overrides."
  value       = local.infrastructure_vips
}

output "global_topology_identity" {
  description = "Pass-through of foundation-libvirt-resources topology identity map."
  value       = local.state.network.global_topology_identity
}

output "global_topology_network" {
  description = "Pass-through of foundation-libvirt-resources topology network map."
  value       = local.state.network.global_topology_network
}

output "global_network_baseline" {
  description = "Pass-through of foundation-libvirt-resources global network baseline (global_mtu, global_mss)."
  value       = local.state.network.global_network_baseline
}

output "hostonly_addresses" {
  description = "Static HostOnly interface addresses per Talos node."
  value       = module.platform_cilium_frontend.hostonly_addresses
}

output "bootstrap_node_key" {
  description = "The node key used as the etcd bootstrap and Kubernetes API endpoint target."
  value       = module.platform_cilium_frontend.bootstrap_node_key
}
