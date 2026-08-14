
data "terraform_remote_state" "vault_bootstrapper" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}

data "terraform_remote_state" "network" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-libvirt-resources" }
}

# `helm_template` renders template manifests without active API server connectivity.
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
    l2announcements      = { enabled = true }
    hubble               = { enabled = false } # Disable Hubble to prevent persistent state drift.

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
