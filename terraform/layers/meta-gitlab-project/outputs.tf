
output "project_id" {
  description = "Numeric identifier of the project 'meta-platform'."
  value       = module.provisioner_gitlab_project.project_id
}
