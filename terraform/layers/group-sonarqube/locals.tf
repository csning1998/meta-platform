
locals {
  # Reads Vault token directly from host token-helper file to break cyclic authentication dependencies
  # during initialization.
  vault_token = trimspace(file(pathexpand("~/.vault-token")))
}
