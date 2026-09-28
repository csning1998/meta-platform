
output "auth_backend_path" {
  description = "Mount path of the shared GitLab JWT auth backend"
  value       = local.jwt_auth_backend_path
}

output "gitlab_ci_with_code_reviewer_role" {
  description = "JWT auth backend role name for the gitlab-ci-with-code-reviewer repository"
  value       = module.gitlab_ci_with_code_reviewer.role_name
}
