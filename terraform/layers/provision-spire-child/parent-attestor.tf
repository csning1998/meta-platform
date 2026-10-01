
# ServiceAccount grants k8s:psat node attestation permissions (TokenReview, Pod/Node inspection) for SPIRE parent.
resource "kubernetes_service_account_v1" "parent_attestor" {
  metadata {
    name      = local.chart.parent_attestor_sa
    namespace = kubernetes_namespace_v1.spire_system.metadata[0].name
  }
}

resource "kubernetes_cluster_role_v1" "parent_attestor" {
  metadata {
    name = local.chart.parent_attestor_rbac
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
    name = local.chart.parent_attestor_rbac
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
    name      = local.chart.parent_attestor_sa
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
  provider = vault.bastion

  mount = "secret"
  name  = local.kv_path.parent_attestor

  data_json = jsonencode({
    kubeconfig_b64 = base64encode(yamlencode({
      apiVersion        = "v1"
      kind              = "Config"
      "current-context" = local.cluster_name
      clusters = [{
        name = local.cluster_name
        cluster = {
          server                       = local.api_server_vip_url
          "certificate-authority-data" = base64encode(data.kubernetes_config_map_v1.root_ca.data["ca.crt"])
        }
      }]
      users = [{
        name = local.chart.parent_attestor_sa
        user = { token = kubernetes_secret_v1.parent_attestor_token.data["token"] }
      }]
      contexts = [{
        name    = local.cluster_name
        context = { cluster = local.cluster_name, user = local.chart.parent_attestor_sa }
      }]
    }))
  })
}

# Executes remote registration of child server identity and upstream agent node aliases on the SPIRE parent.
module "parent_registration" {
  source = "../../modules/kvm-provisioning/cluster-provision/ansible-runner"

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
  # Both runner modules take this value, and the value stays identical for both modules because the modules share one inventory file.
  ansible_status_trigger = {
    attestor_token_uid = kubernetes_secret_v1.parent_attestor_token.metadata[0].uid
    kv_version         = vault_kv_secret_v2.parent_attestor.metadata["version"]
    spiffe_ids         = local.spiffe_id
    agent_endpoint     = "${local.agent_vip}:${local.agent_port}"
    operator_identity  = { for key, op in local.terraform_operators : key => op.spiffe_path }
  }
}

# The operator workstation runs a second agent which attests to the child server. The Terraform operator identities
# register with the child, and the layers of the Downstream Vault log in with the JWT-SVID of the child.
module "operator_registration" {
  source = "../../modules/kvm-provisioning/cluster-provision/ansible-runner"

  depends_on = [
    helm_release.spire_nested,
    vault_kv_secret_v2.registrar,
    kubernetes_manifest.agent_ip_pool,
    kubernetes_manifest.agent_l2_announcement,
  ]

  status_trigger = local.ansible_status_trigger
  ansible_config = local.ansible_config
  inventory_data = local.inventory_data
  extra_vars     = local.ansible_extra_vars
  playbook_paths = [
    "${local.ansible_config.root_path}/playbooks/playbook_host_terraform_operator_child.yaml"
  ]
  ansible_tags = ["always", "spire_agent", "terraform_operator_identity", "terraform_operator_verify"]
}
