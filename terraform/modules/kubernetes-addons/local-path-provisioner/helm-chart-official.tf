
# The helper pods mount host paths, which the default Talos pod security admission rejects outside a privileged namespace.
resource "kubernetes_namespace_v1" "local_path_storage" {
  metadata {
    name = var.helm_config.namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "local_path_provisioner" {
  name       = "local-path-provisioner"
  repository = var.helm_config.chart_repository
  chart      = "local-path-provisioner"
  version    = var.helm_config.version
  namespace  = kubernetes_namespace_v1.local_path_storage.metadata[0].name

  values = [yamlencode({
    storageClass = {
      name          = var.storage_config.class_name
      defaultClass  = var.storage_config.default_class
      reclaimPolicy = var.storage_config.reclaim_policy
    }
    nodePathMap = [{
      node  = "DEFAULT_PATH_FOR_NON_LISTED_NODES"
      paths = [var.storage_config.node_path]
    }]
  })]
}
