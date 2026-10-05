
data "terraform_remote_state" "platform_spire_child" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-spire-child" }
}

data "terraform_remote_state" "security_vault_downstream_tenants" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-vault-downstream-tenants" }
}

data "terraform_remote_state" "platform_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/platform-spire-parent-frontend" }
}

data "terraform_remote_state" "security_vault_downstream_pki" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/security-pki" }
}

ephemeral "vault_kv_secret_v2" "spire_child" {
  provider = vault.downstream

  mount = "secret"
  name  = local.kv_path.cluster
}

# Cluster readiness checks MUST re-validate quorum convergence during apply operations
# because concurrent disk I/O from sibling layers destabilizes etcd consensus.
ephemeral "talos_cluster_health" "this" {
  client_configuration = {
    ca_certificate     = ephemeral.vault_kv_secret_v2.spire_child.data["talos_ca_certificate_b64"]
    client_certificate = ephemeral.vault_kv_secret_v2.spire_child.data["talos_client_certificate_b64"]
    client_key         = ephemeral.vault_kv_secret_v2.spire_child.data["talos_client_key_b64"]
  }
  control_plane_nodes = values(local.state.platform_spire_child.hostonly_addresses)
  endpoints           = values(local.state.platform_spire_child.hostonly_addresses)

  timeout = "10m"
}

# The cluster CA reaches the Parent through a kubeconfig. The CA is public, and reading the CA here keeps the kubeconfig
# free of the ephemeral admin credentials.
data "kubernetes_config_map_v1" "root_ca" {
  depends_on = [ephemeral.talos_cluster_health.this]

  metadata {
    name      = "kube-root-ca.crt"
    namespace = "kube-system"
  }
}
