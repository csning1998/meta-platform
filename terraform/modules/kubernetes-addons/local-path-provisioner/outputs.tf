
output "storage_class_name" {
  description = "Name of the StorageClass which the provisioner serves."
  value       = var.storage_config.class_name
  depends_on  = [helm_release.local_path_provisioner]
}
