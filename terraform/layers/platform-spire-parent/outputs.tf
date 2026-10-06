
output "service_vip" {
  description = "The virtual IP assigned to the SPIRE Parent service from Cilium topology."
  value       = module.terraform_layer_context.primary_net_config.lb_config.vip
}

output "node_exporter_targets" {
  description = "Node Exporter scrape targets (per-node IPs and port) for the SPIRE Parent VM fleet."
  value = {
    ips  = module.terraform_layer_context.svc_network.node_ips
    port = module.terraform_layer_context.node_exporter_port
  }
}

output "spire_agent_bootstrap" {
  description = "Values a SPIRE Agent consumer needs to reach and trust this SPIRE Parent."
  value = {
    node_ip      = one(module.terraform_layer_context.svc_network.node_ips)
    ssh_host     = "${module.terraform_layer_context.svc_identity.cluster_name}-node-00"
    trust_domain = local.spire_trust_domain
    server_port  = local.spire_server_port
  }
}

output "spire_oidc_auth_backend_path" {
  description = "Mount path at which a Vault instance mounts the JWT backend which trusts the OIDC Discovery Provider of the SPIRE Parent. The Bastion Vault does not mount the backend."
  value       = "${module.terraform_layer_context.svc_identity.cluster_name}-jwt-svid-provider"
}

output "spire_oidc_discovery_url" {
  description = "Issuer URL of the OIDC Discovery Provider of the SPIRE Parent, which equals the iss claim of every JWT-SVID of the SPIRE Parent and the bound_issuer of the JWT backend of the Downstream Vault."
  value       = "https://${local.spire_parent_node_ip}:${local.spire_oidc_port}"
}

output "spire_oidc_discovery_ca_pem" {
  description = "CA chain of the listener of the OIDC Discovery Provider: the Bastion root and the pki-platform intermediate."
  value       = local.oidc_ca_chain_pem
}

output "spire_upstream_ca_pem" {
  description = "Certificate of pki-spire, the upstream root of the SPIRE trust bundle, which an upstream agent of the SPIRE Child trusts before its first attestation."
  value       = local.bastion_pki_spire.cert_pem
}
