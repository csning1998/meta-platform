
output "terraform_operator" {
  description = "Identity of the local Terraform operator of each consumer service, keyed by service name: the JWT role name to log in with, and the name of its JWT-SVID fetch wrapper."
  value = {
    for name, spec in local.spire_terraform_operator_specs : spec.service_name => {
      role_name    = name
      wrapper_name = "spire-fetch-${name}"
    }
  }
}
