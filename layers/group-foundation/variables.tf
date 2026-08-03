
variable "gitlab_token" {
  description = "GitLab Personal Access Token (PAT) configured with the mandatory 'api' scope for GitLab provider authentication."
  type        = string
  sensitive   = true
}
