
resource "libvirt_network" "nat_networks" {
  for_each = var.create_networks ? var.network_infrastructure : {}

  name      = each.value.nat.name
  autostart = true
  bridge    = { name = each.value.nat.bridge_name }
  forward   = { mode = "nat" }

  ips = [{
    address = each.value.nat.gateway
    prefix  = each.value.nat.prefix
    dhcp = {
      ranges = each.value.nat.dhcp != null ? [{
        start = each.value.nat.dhcp.start
        end   = each.value.nat.dhcp.end
      }] : []
    }
  }]
}

resource "libvirt_network" "hostonly_networks" {
  for_each = var.create_networks ? var.network_infrastructure : {}

  name      = each.value.hostonly.name
  autostart = true
  bridge    = { name = each.value.hostonly.bridge_name }
  forward   = { mode = "route" }

  ips = [{
    address = each.value.hostonly.gateway
    prefix  = each.value.hostonly.prefix
  }]
}

resource "libvirt_network" "service_networks" {
  for_each = var.create_networks ? { for seg in var.talos_cluster_service_segments : seg.name => seg } : {}

  name      = each.value.name
  autostart = true
  bridge    = { name = each.value.bridge_name }
  forward   = { mode = "route" }

  ips = [{
    address = cidrhost(each.value.cidr, 1)
    prefix  = tonumber(split("/", each.value.cidr)[1])
  }]
}

# Shared boot media volume. Talos defers disk partitioning and OS installation until network
# machine configuration deployment, maintaining this volume attached as a read-only CD-ROM device.
resource "libvirt_volume" "talos_iso" {
  name = "talos-metal-amd64-${basename(dirname(var.talos_iso_path))}.iso"
  pool = var.talos_cluster_vm_config.storage_pool_name

  target = {
    format = {
      type = "iso"
    }
  }

  create = {
    content = {
      url = abspath(var.talos_iso_path)
    }
  }
}

# Unformatted OS target volume. Talos partitions and installs the operating system directly
# upon machine configuration receipt, bypassing base image and cloud-init dependencies.
resource "libvirt_volume" "os_disk" {
  for_each = var.talos_cluster_vm_config.nodes

  pool     = var.talos_cluster_vm_config.storage_pool_name
  name     = "${each.key}-os.qcow2"
  capacity = each.value.os_disk_capacity_gib * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_domain" "nodes" {
  depends_on = [
    libvirt_network.service_networks,
    libvirt_network.nat_networks,
    libvirt_network.hostonly_networks,
    libvirt_volume.os_disk,
    libvirt_volume.talos_iso,
  ]

  for_each = var.talos_cluster_vm_config.nodes

  name        = each.key
  type        = "kvm"
  vcpu        = each.value.vcpu
  memory      = each.value.ram
  memory_unit = "MiB"
  autostart   = false
  running     = true

  os  = { type = "hvm", arch = "x86_64" }
  cpu = { mode = "host-passthrough" }

  devices = {
    disks = [
      # Primary boot device. Unpartitioned volumes lack bootable sectors, causing firmware boot
      # sequence fallthrough to secondary ISO media prior to OS installation.
      {
        device = "disk"
        target = { dev = "vda", bus = "virtio" }
        driver = { type = "qcow2" }
        boot   = { order = 1 }
        source = {
          volume = {
            pool   = var.talos_cluster_vm_config.storage_pool_name
            volume = libvirt_volume.os_disk[each.key].name
          }
        }
      },
      # Secondary boot device for installation ISO. Kernel parameter `talos.halt_if_installed`
      # halts execution on subsequent boots to prevent redundant OS re-installation.
      {
        device = "cdrom"
        target = { dev = "sda", bus = "sata" }
        boot   = { order = 2 }
        source = {
          volume = {
            pool   = var.talos_cluster_vm_config.storage_pool_name
            volume = libvirt_volume.talos_iso.name
          }
        }
      }
    ]

    interfaces = [
      for iface in each.value.interfaces : {
        type  = "network"
        mac   = { address = iface.mac }
        model = { type = "virtio" }
        source = {
          network = {
            network = iface.network_name
          }
        }
      }
    ]

    consoles = [
      {
        type   = "pty"
        target = { port = 0, type = "serial" }
      },
      {
        type   = "pty"
        target = { port = 1, type = "virtio" }
      }
    ]

    # Bound to the hypervisor's loopback interface; console access from elsewhere requires
    # an SSH tunnel to the hypervisor rather than a direct, unauthenticated network path to
    # a control-plane node's serial console.
    graphics = [{
      vnc = { listen = "127.0.0.1", autoport = "yes" }
    }]

    videos = [{
      model = {
        type    = "vga"
        vram    = 16384
        primary = "yes"
        heads   = 1
      }
    }]
  }

  # The libvirt provider reports disk and interface diffs that are not meaningful after first
  # boot. A subsequent node_config topology change is masked by the same ignore and requires
  # terraform apply -replace on the affected node.
  lifecycle {
    ignore_changes = [devices]
  }
}

data "libvirt_domain_interface_addresses" "nodes" {
  for_each = var.talos_cluster_vm_config.nodes

  # Domain interface address queries require domain UUIDs. Numeric domain runtime IDs (`id`) are rejected.
  domain = libvirt_domain.nodes[each.key].uuid
  source = "lease"

  # The lease table read here feeds maintenance_addresses' one(), which returns null on zero
  # matches and errors opaquely on more than one. This surfaces the same failure attributing
  # it to the node and NAT MAC actually at fault.
  lifecycle {
    postcondition {
      condition = length([
        for addr in flatten([
          for iface in self.interfaces :
          iface.addrs if lower(iface.hwaddr) == lower(var.talos_cluster_vm_config.nodes[each.key].interfaces[0].mac)
        ]) : addr.addr if addr.type == "ipv4"
      ]) == 1
      error_message = "Expected exactly one IPv4 DHCP lease on the NAT interface (MAC ${var.talos_cluster_vm_config.nodes[each.key].interfaces[0].mac}) for node '${each.key}'; the maintenance-mode address is not yet stable."
    }
  }
}
