
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

# Cluster CNI template inline manifest provisions networking prerequisites for downstream SPIRE child workloads.
data "helm_template" "cilium" {
  name         = "cilium"
  namespace    = "kube-system"
  repository   = "https://helm.cilium.io/"
  chart        = "cilium"
  version      = var.cilium_chart_version
  kube_version = var.talos_kubernetes_version

  # Talos denies `SYS_MODULE` capability to workloads, requiring explicit capability listing.
  # Host OS natively provisions cgroupv2 and bpffs mounts.
  values = [yamlencode({
    ipam                 = { mode = "kubernetes" }
    kubeProxyReplacement = true

    # L2 announcement enables upstream Vault discovery of the child SPIRE OIDC provider address.
    l2announcements = { enabled = true }
    hubble          = { enabled = false }

    MTU = local.net_mtu
    bpf = { masquerade = true }

    # Route API server connections to node-local KubePrism endpoints. Disabling kube-proxy
    # prevents ClusterIP routing prior to CNI initialization.
    k8sServiceHost = "localhost"
    k8sServicePort = var.kubeprism_port

    cgroup = {
      autoMount = { enabled = false }
      hostRoot  = "/sys/fs/cgroup"
    }

    securityContext = {
      capabilities = {
        ciliumAgent = [
          "CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN",
          "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID",
        ]
        cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
      }
    }
  })]
}
