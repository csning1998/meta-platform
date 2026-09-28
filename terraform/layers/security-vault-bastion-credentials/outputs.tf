
# A KV mount and path are coordinates of the secret. nonsensitive() strips the blanket mark
# the module puts on the whole secret object.
output "guest_secret_paths" {
  description = "Bastion Vault KV mount and path for every provisioned guest identity, keyed by service name."
  value = {
    for name, m in module.service_identity : name => {
      mount = nonsensitive(m.secret.mount)
      path  = nonsensitive(m.secret.path)
    }
  }
}
