
output "terraform_operator" {
  description = "Identity of the local Terraform operator of each consumer component, keyed as in _spire_operator_targets: the JWT role name on the Downstream Vault, the name of the JWT-SVID fetch wrapper, the SPIFFE path, and the catalog service, component, and cluster name."
  value = {
    for name, spec in local.spire_terraform_operator_specs : spec.output_key => {
      role_name    = name
      wrapper_name = "spire-fetch-${name}"
      spiffe_path  = spec.spiffe_path
      service      = spec.service
      component    = spec.component
      cluster_name = spec.cluster_name
    }
  }
}
