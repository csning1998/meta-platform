
output "spire_child" {
  description = "SPIRE child trust domain coordinates, server SPIFFE ID, JWT issuer, and downstream Vault auth mount path."
  value = {
    trust_domain             = local.trust_domain
    server_spiffe_id         = local.spiffe_id.child_server
    upstream_agent_alias     = local.spiffe_id.upstream_agent_alias
    jwt_issuer               = local.jwt_issuer
    jwt_svid_auth_mount_path = vault_jwt_auth_backend.spire_child.path
  }
}

output "spire_child_agent_endpoint" {
  description = "Address and port at which the agents of downstream VMs attest to the child SPIRE server."
  value = {
    address      = local.agent_vip
    port         = local.agent_port
    trust_domain = local.trust_domain
  }
}

output "spire_child_registrar_kv_path" {
  description = "Downstream KV path of the kubeconfig which the registrar of the Child holds, for the roles that run spire-server in the pod of the Child server."
  value       = local.kv_path.registrar
}
