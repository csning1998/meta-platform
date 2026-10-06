
output "foundation_topology" {
  description = "Pass-through of the foundation-libvirt-resources topology object."
  value       = local.state.foundation_libvirt_resources.foundation_topology
}

output "foundation_network_global" {
  description = "Pass-through of the foundation-libvirt-resources global facts object."
  value       = local.state.foundation_libvirt_resources.foundation_network_global
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

output "talos_cluster" {
  description = "Facts of the SPIRE Child Talos cluster."
  value = {
    hostonly_addresses = module.establish_platform_spire_child_talos_cluster.hostonly_addresses
    bootstrap_node_key = module.establish_platform_spire_child_talos_cluster.bootstrap_node_key
  }
}
