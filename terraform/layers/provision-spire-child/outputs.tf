
output "spire_child" {
  description = "SPIRE child trust domain coordinates, server SPIFFE ID, JWT issuer, and downstream Vault auth mount path."
  value = {
    trust_domain             = local.trust_domain
    server_spiffe_id         = local.spiffe_id.child_server
    upstream_agent_alias     = local.spiffe_id.upstream_agent_alias
    jwt_issuer               = local.jwt_issuer
    jwt_svid_auth_mount_path = local.jwt_svid_auth_mount_path
  }
}

output "terraform_operator_downstream" {
  description = "Terraform operator identities of the Child, keyed as terraform_operator of provision-spire-parent: the JWT role name, the name of the Child JWT-SVID fetch wrapper, and the audience of the JWT-SVID."
  value = {
    for key, op in local.terraform_operators : key => {
      role_name    = op.role_name
      wrapper_name = "spire-fetch-${op.role_name}-child"
      audience     = local.downstream_audience
    }
  }
}

output "spire_child_agent_endpoint" {
  description = "Address and port at which the agents of downstream VMs and of the operator workstation attest to the child SPIRE server."
  value = {
    address      = local.agent_vip
    port         = local.agent_port
    trust_domain = local.trust_domain
  }
}

output "spire_child_registrar_kv_path" {
  description = "Bastion KV path of the kubeconfig which the registrar of the Child holds, for the roles that run spire-server in the pod of the Child server."
  value       = local.kv_path.registrar
}
