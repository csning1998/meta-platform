output "inventory_content" {
  description = "Generated YAML content of the Ansible inventory file."
  value       = local_file.inventory.content
}

output "inventory_file_path" {
  description = "Filesystem path to the written Ansible inventory file."
  value       = local_file.inventory.filename
}
