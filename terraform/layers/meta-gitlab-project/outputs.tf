
output "project_id" {
  description = "Numeric identifier of the project 'platform-foundation'."
  value       = module.provisioner_gitlab_project.project_id
}
