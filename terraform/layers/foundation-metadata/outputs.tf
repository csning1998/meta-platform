
output "global_domain_suffix" {
  description = "The root domain suffix (e.g., iac.local) for all downstream consumer projects."
  value       = var.domain_suffix
}

output "global_pki_config" {
  description = "Global PKI identity settings for downstream layers (e.g. Vault PKI)."
  value       = var.pki_config
}

output "global_network_baseline" {
  description = "Base network configuration including CIDR, VIP offsets, and global MTU/MSS settings."
  value       = var.network_baseline
}
