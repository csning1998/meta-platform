
data "terraform_remote_state" "foundation_vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base_parent_group_governance}/foundation-vault-bastion" }
}

data "terraform_remote_state" "foundation_libvirt_resources" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "platform_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-spire-parent-frontend" }
}

data "terraform_remote_state" "provision_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/provision-spire-parent-frontend" }
}

# Vault authentication MUST obtain ephemeral JWT-SVID credentials on every execution to prevent state file persistence.
data "external" "spire_jwt" {
  program = ["/usr/local/bin/${local.terraform_operator.wrapper_name}"]
}

data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api.version}/experimental-install.yaml"

  lifecycle {
    postcondition {
      condition     = sha256(self.response_body) == var.gateway_api.sha256
      error_message = "The Gateway API ${var.gateway_api.version} experimental-install.yaml does not match the pinned digest."
    }
  }
}
