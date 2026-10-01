
/**
 * Implicit sub-ordering within tier 40:
 * this layer reads keycloak_oidc (provision-keycloak-oidc),
 * which must apply first so that Keycloak OIDC client credentials exist before Harbor SSO is configured.
 * Downstream layers that read this layer's outputs (gitlab-frontend, gitlab-runner, harbor-frontend,
 * observability-frontend) therefore have an implicit three-level sequence within tier 40:
 * (1) keycloak-oidc, (2) harbor-origin-frontend, (3) the above consumers.
 */

data "terraform_remote_state" "security_vault_downstream_tenants" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-vault-downstream-tenants" }
}

data "terraform_remote_state" "security_vault_downstream_pki" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-pki" }
}

data "terraform_remote_state" "platform_harbor_origin_frontend" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-harbor-origin-frontend" }
}

data "terraform_remote_state" "provision_keycloak_oidc" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-keycloak-oidc" }
}

ephemeral "vault_kv_secret_v2" "harbor_origin" {
  provider = vault.downstream
  mount    = "secret"
  name     = local.kv_paths["harbor-origin"]["frontend"].app
}

data "terraform_remote_state" "provision_spire_child" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-spire-child" }
}

# The downstream Vault trusts the SPIRE Child only, and so the operator logs in with a JWT-SVID which the Child issued.
data "external" "spire_jwt_downstream" {
  program = ["/usr/local/bin/${local.state.provision_spire_child.terraform_operator_downstream["harbor-origin"].wrapper_name}"]
}
