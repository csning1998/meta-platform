
variable "gitlab_token" {
  description = "GitLab Personal Access Token (PAT) configured with the mandatory 'api' scope for provider authentication and remote state retrieval."
  type        = string
  sensitive   = true
}
