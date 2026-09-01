
output "service_vip" {
  description = "The virtual IP assigned to the SPIRE Parent service from Cilium topology."
  value       = module.context.primary_net_config.lb_config.vip
}

output "node_exporter_targets" {
  description = "Node Exporter scrape targets (per-node IPs and port) for the SPIRE Parent VM fleet."
  value = {
    ips  = module.context.svc_network.node_ips
    port = module.context.node_exporter_port
  }
}

output "spire_agent_bootstrap" {
  description = "Values a SPIRE Agent consumer needs to reach and trust this SPIRE Parent."
  value = {
    node_ip      = one(module.context.svc_network.node_ips)
    trust_domain = local.spire_trust_domain
    server_port  = local.spire_server_port
  }
}

output "spire_oidc_auth_backend_path" {
  description = "Mount path of the SPIRE Parent workload JWT-SVID federation backend, for role provisioning by workload-identity-federation module callers."
  value       = vault_jwt_auth_backend.spire_oidc.path
}
