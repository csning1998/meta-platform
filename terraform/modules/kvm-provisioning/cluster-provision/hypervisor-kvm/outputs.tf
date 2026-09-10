
output "provisioned_nodes" {
  description = "Map of provisioned KVM nodes with their actual state."
  value = {
    for key, domain in libvirt_domain.nodes : key => {
      ip                   = var.guest_config.all_nodes_map[key].ip
      id                   = domain.id
      name                 = domain.name
      vcpu                 = domain.vcpu
      ram_size_mib         = domain.memory
      os_disk_capacity_gib = var.guest_config.all_nodes_map[key].os_disk_capacity_gib
      attached_volumes     = var.guest_config.all_nodes_map[key].attached_volumes
    }
  }
}

output "infrastructure_config" {
  description = "The actual infrastructure configuration used by Libvirt."
  value       = var.libvirt_infrastructure
}

output "guest_status_trigger" {
  description = "A trigger to indicate completion of VM provisioning"
  value       = { for key, domain in libvirt_domain.nodes : key => domain.id }
}

output "os_disk_paths" {
  description = "Host filesystem path per node's OS disk volume. For os_disk_format = raw, an Ansible role targets these paths with qemu-img convert before start_domains flips to true."
  value       = { for key, vol in libvirt_volume.os_disk : key => vol.path }
}

output "guest_host_public_keys" {
  description = "Each node's SSH host public key in known_hosts line format (key type + base64 blob), injected into the guest by cloud-init so known_hosts trust never depends on scanning the network on first connect."
  value       = { for key, k in tls_private_key.guest_host_key : key => trimspace(k.public_key_openssh) }
}
