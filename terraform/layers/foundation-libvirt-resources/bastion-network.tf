
# Derives deterministic node IP allocations across the unmanaged vault-bastion-publish routed network segment.
# first_host reserves host offsets below base offset, while cidr_index_origin anchors address calculation.
locals {
  bastion_network = {
    name                = "vault-bastion-publish"
    first_host          = 20  # Reserves host offsets below the base offset for consumer layer static configurations.
    cidr_index_origin   = 125 # Anchors the address calculation baseline to prevent disruptive guest NIC renumbering across immutable nodes.
    nodes_per_component = 4
  }

  bastion_network_cidr = cidrsubnet(var.network_baseline.cidr_block, var.network_baseline.cidr_subnet_bits, 0)

  bastion_network_addresses = merge([
    for s_name, s in var.service_catalog : {
      for c_name, c in s.components : "${var.project_code}-${s_name}-${c_name}" => [
        for i in range(c.ip_range.end_ip - c.ip_range.start_ip + 1) : format("%s/%d",
          cidrhost(
            local.bastion_network_cidr,
            local.bastion_network.first_host
            + local.bastion_network.nodes_per_component * (c.cidr_index - local.bastion_network.cidr_index_origin)
            + i
          ),
          split("/", local.bastion_network_cidr)[1]
        )
      ]
    }
  ]...)
}

check "bastion_network_derivation" {
  assert {
    condition = alltrue([
      for s in var.service_catalog : alltrue([
        for c in s.components :
        c.cidr_index >= local.bastion_network.cidr_index_origin
        && c.ip_range.end_ip - c.ip_range.start_ip + 1 <= local.bastion_network.nodes_per_component
      ])
    ])
    error_message = "Every component MUST have a cidr_index of at least ${local.bastion_network.cidr_index_origin} and at most ${local.bastion_network.nodes_per_component} nodes for the Bastion network derivation."
  }
}

check "bastion_network_addresses_unique" {
  assert {
    condition     = length(flatten(values(local.bastion_network_addresses))) == length(distinct(flatten(values(local.bastion_network_addresses))))
    error_message = "The derived vault-bastion-publish addresses collide."
  }
}

output "foundation_bastion_network" {
  description = "Derived node IP address allocations on the vault-bastion-publish network segment, keyed by cluster name."
  value = {
    network_name = local.bastion_network.name
    addresses    = local.bastion_network_addresses
  }
}
