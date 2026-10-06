
# Every output is a category object. Terraform does not persist an output whose value is null, hence the runtime object
# always exists, with null fields on the runtime which the catalog does not select.
output "runtime" {
  description = "Runtime of the component in the service catalog, passed through from platform-vault-downstream-frontend: the runtime name, and whether the runtime is Kubernetes native."
  value       = local.vault_downstream_runtime
}

output "talos_cluster" {
  description = "Facts of the in-cluster Vault servers on the Talos runtime, with a null vault_servers on the VM runtime: whether the runtime applies, and the namespace, the pod names in ordinal order, the container, the release revision, and the seal."
  value = {
    enabled       = local.is_runtime_talos
    vault_servers = one(module.helm_chart_vault[*].vault_servers)
  }
}
