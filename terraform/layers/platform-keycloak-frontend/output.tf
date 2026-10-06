
output "keycloak_fqdn" {
  description = "The FQDN of the Keycloak service."
  value       = module.terraform_layer_context.svc_fqdn
}

output "service_vip" {
  description = "The virtual IP assigned to the Keycloak service from Central LB topology."
  value       = module.terraform_layer_context.primary_net_config.lb_config.vip
}

output "topology_node" {
  description = "The actual provisioned configuration for Keycloak node."
  value       = one(module.infra_keycloak_cluster[*].cluster_nodes)
}

output "pki_key" {
  description = "The physical SSoT PKI key associated with the Keycloak service."
  value       = module.terraform_layer_context.primary_context.pki_key
}

output "ssh_config_file_path" {
  description = "The path to the generated SSH configuration file."
  value       = one(module.infra_keycloak_cluster[*].ssh_config_file_path)
}

output "runtime" {
  description = "Runtime of the component in the service catalog."
  value       = local.svc_runtime
}

output "hostonly_addresses" {
  description = "Static HostOnly interface addresses per Talos node. Null on the VM path."
  value       = one(module.infra_keycloak_talos[*].hostonly_addresses)
}

output "bootstrap_node_key" {
  description = "The node key used as the etcd bootstrap and Kubernetes API endpoint target. Null on the VM path."
  value       = one(module.infra_keycloak_talos[*].bootstrap_node_key)
}

output "volume_mount_path" {
  description = "Mount path of the Talos user volume on every node. Null on the VM path."
  value       = one(module.infra_keycloak_talos[*].volume_mount_path)
}

output "cluster_issuer" {
  description = "Coordinates of the cert-manager ClusterIssuer against the Downstream Vault. Null on the VM path."
  value       = one(module.vault_auth_keycloak_talos[*].cluster_issuer)
}

output "external_secrets" {
  description = "Coordinates of the External Secrets Operator against the Downstream Vault. Null on the VM path."
  value       = one(module.vault_auth_keycloak_talos[*].external_secrets)
}
