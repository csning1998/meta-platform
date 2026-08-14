
module "interface_planner" {
  source = "../cluster-provision/lb-interface-planner"

  node_config           = local.interface_planner_node_config
  storage_pool_name     = var.topology_cluster.storage_pool_name
  svc_network           = local.svc_net
  network_infra         = local.infra
  svc_network_map       = var.svc_network_map
  service_segment_names = [for seg in var.network_service_segments : seg.name]
}

module "hypervisor_kvm_talos" {
  source = "../cluster-provision/hypervisor-kvm-talos"

  talos_iso_path                 = var.talos_iso_path
  talos_cluster_vm_config        = local.talos_cluster_vm_config
  network_infrastructure         = var.network_infrastructure_map
  talos_cluster_service_segments = var.network_service_segments
  create_networks                = false
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Configure all nodes as control plane members. Small fixed node counts run combined control plane
# and workload tasks to optimize resource utilization within etcd quorum limits.
data "talos_machine_configuration" "this" {
  for_each = local.talos_cluster_vm_config.nodes

  cluster_name       = var.svc_identity.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.talos_kubernetes_version
  talos_version      = var.talos_version

  config_patches = [
    yamlencode({
      machine = {
        # Explicitly set installer image URI to align installed image release with running ISO media version.
        install = {
          disk  = "/dev/vda"
          image = "ghcr.io/siderolabs/installer:${var.talos_version}"
        }
        # Retain DHCP on interface index 0 for maintenance mode connectivity. Configure explicit static
        # addresses on non-DHCP interfaces (index 1 and above).
        network = {
          interfaces = [
            for iface in slice(each.value.interfaces, 1, length(each.value.interfaces)) : {
              deviceSelector = { hardwareAddr = iface.mac }
              dhcp           = false
              addresses      = iface.addresses
            }
          ]
        }
        # Pin kubelet node IP binding explicitly to the service subnet CIDR block.
        kubelet = { nodeIP = { validSubnets = [local.svc_net.cidr_block] } }
      }
      cluster = {
        network         = { cni = { name = "none" } }
        proxy           = { disabled = true }
        etcd            = { advertisedSubnets = [local.svc_net.cidr_block] }
        inlineManifests = [{ name = "cilium", contents = var.cilium_inline_manifest }]
      }
    })
  ]
}

# Target pre-configuration node maintenance IP addresses resolved from libvirt DHCP leases.
resource "talos_machine_configuration_apply" "this" {
  depends_on = [module.hypervisor_kvm_talos]
  for_each   = local.talos_cluster_vm_config.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  node                        = module.hypervisor_kvm_talos.maintenance_addresses[each.key]
  endpoint                    = module.hypervisor_kvm_talos.maintenance_addresses[each.key]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  node                 = local.hostonly_addresses[local.bootstrap_node_key]
  client_configuration = talos_machine_secrets.this.client_configuration

  timeouts = {
    create = var.bootstrap_timeout
  }
}

data "talos_cluster_health" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = values(local.hostonly_addresses)
  endpoints            = values(local.hostonly_addresses)

  timeouts = {
    read = var.health_timeout
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [data.talos_cluster_health.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.hostonly_addresses[local.bootstrap_node_key]
}
