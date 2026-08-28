
# Vault KV paths written by this layer, for documentation and cross-layer reference.
output "credential_paths" {
  description = "Mount-relative Vault KV paths of all generated credentials."
  value = {
    keycloak_frontend      = module.keycloak_frontend.path
    harbor_origin_frontend = module.harbor_origin_frontend.path
  }
}
