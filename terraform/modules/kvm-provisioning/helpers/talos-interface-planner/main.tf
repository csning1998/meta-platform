
module "deterministic_mac" {
  source = "../deterministic-mac"

  seeds = merge([
    for node_name, node_spec in var.node_config : {
      for net, cidr in node_spec.extra_networks : "${node_name}/${net}" => "${cidr}-${net}"
    }
  ]...)
}
