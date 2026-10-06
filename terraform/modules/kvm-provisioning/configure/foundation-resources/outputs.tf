
output "topology" {
  description = "Topology of every service segment: identity, network, service segments, and the physical realization that bridges identity and service VIPs, all keyed by the SSoT identity."
  value = {
    identity = module.service_catalog.topology_identity
    network  = module.service_catalog.topology_network
    segments = local.net_service_segments

    infrastructure = {
      for seg in local.net_service_segments : seg.name => {
        # 1. Physical Infrastructure (Libvirt bridges, IPs)
        network = local.net_infrastructure[seg.name]

        lb_config = {
          vip   = seg.vip
          ports = seg.ports
          tags  = seg.tags
        }

        # Runtime enum from service_catalog (baremetal, docker, podman, microk8s, kubeadm, minikube, talos, external).
        # provision-cilium-hubble and platform-haproxy-frontend read the runtime to decide which of the two owns a segment VIP.
        runtime = seg.runtime

        # 3. Available Node IP slots for downstream consumption
        backend_servers = seg.backend_servers
      }
    }

    # Runtimes which run Kubernetes. The consumers split the Kubernetes backends from the external backends by this list.
    kubernetes_native_runtimes = ["talos", "kubeadm", "microk8s", "minikube"]
  }
}

output "global" {
  description = "Global facts shared by every consumer: the network baseline with CIDR, VIP offsets, and MTU and MSS, the root domain suffix, and the hostname to VIP records grouped by IP."
  value = {
    network_baseline = var.network_baseline
    domain_suffix    = var.domain_suffix
    dns_records      = module.service_catalog.dns_records
    dns_mapping = [
      for ip in sort(distinct([for r in local.metadata.global_dns_records : r.ip])) : {
        ip        = ip
        hostnames = sort(distinct([for r in local.metadata.global_dns_records : r.hostname if r.ip == ip]))
      }
    ]
  }
}

output "pki" {
  description = "PKI facts derived from the service catalog: the DNS SANs and organizational context per certificate."
  value = {
    map = module.service_catalog.pki_map
  }
}

output "storage" {
  description = "Physical realization of the storage layout, ready for KVM instances, and the calculated volume attributes of the pools and data disks."
  value = {
    infrastructure = local.global_volume_map
    volume_map     = module.service_catalog.volume_map
  }
}

output "vault_path" {
  description = "Mount-relative Vault KV paths: the credential folder of every service component, nested by service and component, and the SSH identity folder per cluster_name, under which foundation-vault-bastion writes ssh_private_key and ssh_public_key."
  value = {
    credential_paths     = module.service_catalog.credential_paths
    ssh_credential_paths = local.ssh_credential_paths
  }
}

output "ssh" {
  description = "SSH identity inputs keyed by cluster_name. The hosts map is the identity_hosts input of the ssh-identity-bootstrap module."
  value = {
    hosts = local.ssh_hosts
  }
}
