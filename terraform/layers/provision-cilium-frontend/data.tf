
data "terraform_remote_state" "cilium_frontend" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-cilium-frontend" }
}

data "terraform_remote_state" "vault_bootstrapper" {
  backend = "http"
  config  = { address = "${local._state_base_parent_group_governance}/foundation-vault-bastion" }
}

data "terraform_remote_state" "spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-spire-parent-frontend" }
}

# Vault authentication MUST obtain ephemeral JWT-SVID credentials on every execution to prevent state file persistence.
data "external" "spire_jwt" {
  program = ["/usr/local/bin/spire-fetch-${local.cilium_cluster_name}"]
}

ephemeral "vault_kv_secret_v2" "cilium_frontend" {
  mount = "secret"
  name  = "${local.vault_kv_namespace}/cilium/frontend"
}

# Cluster readiness checks MUST re-validate quorum convergence during apply operations
# because concurrent disk I/O from sibling layers destabilizes etcd consensus.
ephemeral "talos_cluster_health" "this" {
  client_configuration = {
    ca_certificate     = ephemeral.vault_kv_secret_v2.cilium_frontend.data["talos_ca_certificate_b64"]
    client_certificate = ephemeral.vault_kv_secret_v2.cilium_frontend.data["talos_client_certificate_b64"]
    client_key         = ephemeral.vault_kv_secret_v2.cilium_frontend.data["talos_client_key_b64"]
  }
  control_plane_nodes = values(local.state.cilium_frontend.hostonly_addresses)
  endpoints           = values(local.state.cilium_frontend.hostonly_addresses)

  timeout = "10m"
}
