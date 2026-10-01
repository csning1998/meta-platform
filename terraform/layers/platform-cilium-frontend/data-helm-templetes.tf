
# Renders template manifests without active API server connectivity.
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

    # The certmanager method issues the Hubble certificates once, where the helm method mints a new CA on every render.
    hubble = {
      enabled = true
      relay   = { enabled = true }
      ui      = { enabled = true }
      tls = {
        auto = {
          enabled              = true
          method               = "certmanager"
          certManagerIssuerRef = local.cluster_issuer.ref
        }
      }
    }

    # The Gateway API CRDs ship as inline manifests of the same machine configuration, and the Cilium operator reads the CRDs at start.
    gatewayAPI = { enabled = true }

    # The VXLAN overhead of 50 bytes yields a pod route MTU of global_mtu - 50, which matches the platform global_mss plus 40.
    MTU = local.net_mtu

    # Retained as the configuration validated for in-cluster traffic. The setting does not resolve SNAT toward external backends, which HAProxy serves instead.
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

data "helm_template" "cert_manager" {
  name         = "cert-manager"
  namespace    = local.cluster_issuer.namespace
  repository   = "https://charts.jetstack.io"
  chart        = "cert-manager"
  version      = var.cert_manager_chart_version
  kube_version = var.talos_kubernetes_version

  values = [yamlencode({
    crds            = { enabled = true }
    startupapicheck = { enabled = false }
  })]
}

# The layer consumes ExternalSecret and ClusterSecretStore alone. The CRDs of the other kinds stay out of the machine configuration.
data "helm_template" "external_secrets" {
  name         = "external-secrets"
  namespace    = local.external_secrets.namespace
  repository   = "https://charts.external-secrets.io"
  chart        = "external-secrets"
  version      = var.external_secrets_chart_version
  kube_version = var.talos_kubernetes_version

  values = [yamlencode({
    installCRDs = true
    crds = {
      createClusterExternalSecret = false
      createSecretStore           = false
      createClusterGenerator      = false
      createClusterPushSecret     = false
      createPushSecret            = false
    }
    processClusterExternalSecret = false
    processSecretStore           = false
    processClusterGenerator      = false
    processClusterPushSecret     = false
    processPushSecret            = false
  })]
}
