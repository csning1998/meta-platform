
output "cluster_vm_config" {
  description = "Fully resolved VM config with pre-computed interfaces, ready for linux-talos-domain."
  value       = local.cluster_vm_config
}

