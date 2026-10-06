
# ServiceAccount grants k8s:psat node attestation permissions (TokenReview, Pod/Node inspection) for SPIRE parent.
resource "kubernetes_service_account_v1" "parent_attestor" {
  metadata {
    name      = local.spire_child_chart.parent_attestor_sa
    namespace = kubernetes_namespace_v1.spire_system.metadata[0].name
  }
}

resource "kubernetes_cluster_role_v1" "parent_attestor" {
  metadata {
    name = local.spire_child_chart.parent_attestor_rbac
  }

  rule {
    api_groups = ["authentication.k8s.io"]
    resources  = ["tokenreviews"]
    verbs      = ["create"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "nodes"]
    verbs      = ["get"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "parent_attestor" {
  metadata {
    name = local.spire_child_chart.parent_attestor_rbac
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.parent_attestor.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.parent_attestor.metadata[0].name
    namespace = kubernetes_service_account_v1.parent_attestor.metadata[0].namespace
  }
}

# External SPIRE parent requires a long-lived service account token for non-projected cluster API authentication.
resource "kubernetes_secret_v1" "parent_attestor_token" {
  metadata {
    name      = local.spire_child_chart.parent_attestor_sa
    namespace = kubernetes_service_account_v1.parent_attestor.metadata[0].namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.parent_attestor.metadata[0].name
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

# Kubeconfig is persisted to Vault KV to prevent plaintext credential exposure in Ansible execution variables.
resource "vault_kv_secret_v2" "parent_attestor" {
  provider = vault.downstream

  mount = "secret"
  name  = local.spire_child_kv_paths.parent_attestor

  data_json = jsonencode({
    kubeconfig_b64 = base64encode(yamlencode({
      apiVersion        = "v1"
      kind              = "Config"
      "current-context" = local.spire_child_cluster_name
      clusters = [{
        name = local.spire_child_cluster_name
        cluster = {
          server                       = local.spire_child_api_server_vip_url
          "certificate-authority-data" = base64encode(data.kubernetes_config_map_v1.root_ca.data["ca.crt"])
        }
      }]
      users = [{
        name = local.spire_child_chart.parent_attestor_sa
        user = { token = kubernetes_secret_v1.parent_attestor_token.data["token"] }
      }]
      contexts = [{
        name    = local.spire_child_cluster_name
        context = { cluster = local.spire_child_cluster_name, user = local.spire_child_chart.parent_attestor_sa }
      }]
    }))
  })
}

# Executes remote registration of child server identity and upstream agent node aliases on the SPIRE parent.
module "spire_parent_registration" {
  source = "../../modules/kvm-provisioning/configure/ansible-runner"

  depends_on = [
    vault_kv_secret_v2.parent_attestor,
    kubernetes_cluster_role_binding_v1.parent_attestor,
  ]

  status_trigger = local.ansible_status_trigger
  ansible_config = local.ansible_config
  inventory_data = local.inventory_data
  extra_vars     = local.ansible_extra_vars
  playbook_paths = [
    "${local.ansible_config.root_path}/playbooks/playbook_provision.yaml"
  ]
  ansible_tags = []
}

locals {
  # A change of the attestor token, the kubeconfig version, or the SPIFFE IDs reruns the registration on the SPIRE Parent.
  ansible_status_trigger = {
    attestor_token_uid = kubernetes_secret_v1.parent_attestor_token.metadata[0].uid
    kv_version         = vault_kv_secret_v2.parent_attestor.metadata["version"]
    spiffe_ids         = local.spiffe_workload_id
    agent_endpoint     = "${local.spire_child_agent_vip}:${local.spire_child_agent_port}"
  }
}
