
output "infrastructure_vips" {
  description = "Aggregated list of all internal service VIPs requiring static route overrides."
  value       = local.infrastructure_vips
}

output "foundation_topology" {
  description = "Pass-through of the foundation-libvirt-resources topology object."
  value       = local.state.foundation_libvirt_resources.foundation_topology
}

output "foundation_global" {
  description = "Pass-through of the foundation-libvirt-resources global facts object."
  value       = local.state.foundation_libvirt_resources.foundation_global
}

output "foundation_vault_path" {
  description = "Pass-through of the foundation-libvirt-resources Vault path object."
  value       = local.state.foundation_libvirt_resources.foundation_vault_path
}

output "foundation_pki" {
  description = "Pass-through of the foundation-libvirt-resources PKI object, whose DNS SANs carry the hostnames of the catalog ingress entries."
  value       = local.state.foundation_libvirt_resources.foundation_pki
}

output "hostonly_addresses" {
  description = "Static HostOnly interface addresses per Talos node."
  value       = module.platform_cilium_frontend.hostonly_addresses
}

output "bootstrap_node_key" {
  description = "The node key used as the etcd bootstrap and Kubernetes API endpoint target."
  value       = module.platform_cilium_frontend.bootstrap_node_key
}

output "in_cluster_trust" {
  description = "Coordinates of the in-cluster trust chain: the ClusterIssuer and its Bastion Vault Kubernetes auth mount, the External Secrets Operator identity, and the KV path of the Hubble UI credentials."
  value = {
    cluster_issuer = {
      name            = local.cluster_issuer.name
      namespace       = local.cluster_issuer.namespace
      service_account = local.cluster_issuer.service_account
      auth_path       = vault_auth_backend.kubernetes.path
      role_name       = vault_kubernetes_auth_backend_role.cluster_issuer.role_name
      pki_mount_path  = local.cluster_issuer.pki_mount_path
      issue_path      = local.cluster_issuer.issue_path
    }
    external_secrets = {
      namespace       = local.external_secrets.namespace
      service_account = local.external_secrets.service_account
      role_name       = vault_kubernetes_auth_backend_role.external_secrets.role_name
    }
    hubble_ui_kv_path = local.kv_hubble_ui_path
  }
}
