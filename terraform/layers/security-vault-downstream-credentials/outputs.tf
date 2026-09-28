
# A KV mount and path are coordinates of the secret. nonsensitive() strips the blanket mark
# the module puts on the whole secret object.
output "credential_paths" {
  description = "Downstream Vault KV mount and path of every generated credential, keyed by service name."
  value = {
    keycloak_frontend      = { mount = nonsensitive(module.keycloak_frontend.secret.mount), path = nonsensitive(module.keycloak_frontend.secret.path) }
    harbor_origin_frontend = { mount = nonsensitive(module.harbor_origin_frontend.secret.mount), path = nonsensitive(module.harbor_origin_frontend.secret.path) }
  }
}
