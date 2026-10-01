
output "terraform_operator" {
  description = "Identity of the local Terraform operator of each consumer component, keyed as in _spire_operator_targets: the JWT role name to log in with, and the name of its JWT-SVID fetch wrapper."
  value = {
    for name, spec in local.spire_terraform_operator_specs : spec.output_key => {
      role_name    = name
      wrapper_name = "spire-fetch-${name}"
      spiffe_path  = spec.spiffe_path
    }
  }
}
