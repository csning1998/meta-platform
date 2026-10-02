
output "foundation_topology" {
  description = "Topology of every service segment: identity, network, service segments, and the physical realization that bridges identity and service VIPs, all keyed by the SSoT identity."
  value = {
    identity       = module.foundation_libvirt_resources.global_topology_identity
    network        = module.foundation_libvirt_resources.global_topology_network
    segments       = module.foundation_libvirt_resources.service_segments
    infrastructure = module.foundation_libvirt_resources.infrastructure_map

    # Runtimes which run Kubernetes. The consumers split the Kubernetes backends from the external backends by this list.
    kubernetes_native_runtimes = ["talos", "kubeadm", "microk8s", "minikube"]
  }
}

output "foundation_global" {
  description = "Global facts shared by every consumer: network baseline, root domain suffix, and the hostname to VIP records."
  value = {
    network_baseline = module.foundation_libvirt_resources.global_network_baseline
    domain_suffix    = module.foundation_libvirt_resources.global_domain_suffix
    dns_records      = module.foundation_libvirt_resources.global_dns_records
    dns_mapping      = module.foundation_libvirt_resources.dns_mapping
  }
}

output "foundation_pki" {
  description = "PKI facts derived from the service catalog: the DNS SANs and organizational context per certificate."
  value = {
    map = module.foundation_libvirt_resources.global_pki_map
  }
}

output "foundation_storage" {
  description = "Physical realization of the storage layout: the pools and data disks, and the calculated volume attributes."
  value = {
    infrastructure = module.foundation_libvirt_resources.storage_infrastructure_map
    volume_map     = module.foundation_libvirt_resources.global_volume_map
  }
}

output "foundation_vault_path" {
  description = "Vault KV coordinates of the service catalog: the project_code segment, the folder of each component, the leaf paths below each component folder, the SSH identity leaf keyed by cluster_name, and the project-wide guest VM secret."
  value = {
    project_code     = local.project_code
    credential_paths = module.foundation_libvirt_resources.global_credential_paths
    kv_paths         = local.kv_paths
    ssh_credential_paths = {
      for key, base in module.foundation_libvirt_resources.ssh_credential_paths : key => "${base}/${local.kv_leaf.ssh}"
    }
  }
}

output "foundation_ssh" {
  description = "Local file paths of the SSH client material written by this layer, keyed by cluster_name. The known_hosts path is shared with the ha-service-kvm-general instance of the same cluster_name."
  value = {
    identity_key_paths = module.ssh_identity_bootstrap.identity_key_private_paths
    public_key_paths   = module.ssh_identity_bootstrap.identity_key_public_paths
    config_paths       = module.ssh_identity_bootstrap.host_config_paths
    known_hosts_paths  = module.ssh_identity_bootstrap.known_hosts_paths
    usernames          = { for key, host in module.foundation_libvirt_resources.ssh_hosts : key => host.nodes[0].user if length(host.nodes) > 0 }
  }
}
