
output "foundation_topology" {
  description = "Pass-through of the foundation-libvirt-resources topology object."
  value       = local.state.foundation_libvirt_resources.foundation_topology
}

output "foundation_global" {
  description = "Pass-through of the foundation-libvirt-resources global facts object."
  value       = local.state.foundation_libvirt_resources.foundation_global
}

output "foundation_pki" {
  description = "Pass-through of the foundation-libvirt-resources PKI object."
  value       = local.state.foundation_libvirt_resources.foundation_pki
}

output "foundation_vault_path" {
  description = "Pass-through of the foundation-libvirt-resources Vault path object."
  value       = local.state.foundation_libvirt_resources.foundation_vault_path
}

output "foundation_ssh" {
  description = "Pass-through of foundation SSH metadata for downstream SPIRE parent host connectivity."
  value       = local.state.foundation_libvirt_resources.foundation_ssh
}

output "hostonly_addresses" {
  description = "Static HostOnly interface addresses per Talos node."
  value       = module.platform_spire_child.hostonly_addresses
}

output "bootstrap_node_key" {
  description = "The node key used as the etcd bootstrap and Kubernetes API endpoint target."
  value       = module.platform_spire_child.bootstrap_node_key
}
