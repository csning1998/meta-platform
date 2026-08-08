
locals {
  # Uses read_api CLI credentials for state authentication to prevent higher-privilege token persistence
  # in local terraform_remote_state config blocks.
  _gl_creds   = jsondecode(file(pathexpand("~/.terraform.d/credentials.tfrc.json")))
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_auth = {
    username = "oauth2"
    password = local._gl_creds.credentials["gitlab.com"].token
  }

  # Reads Vault token directly from host token-helper file to break cyclic authentication dependencies
  # during initialization.
  vault_token = trimspace(file(pathexpand("~/.vault-token")))
}
