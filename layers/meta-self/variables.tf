
variable "gitlab_token" {
  description = "GitLab Personal Access Token (PAT) configured with the mandatory 'api' scope for provider authentication and remote state retrieval."
  type        = string
  sensitive   = true
}

variable "claude_api_key" {
  description = "Specifies the Anthropic API key consumed by this project's claude-code-review CI job."
  type        = string
  default     = ""
  sensitive   = true
}

variable "gemini_api_key" {
  description = "Specifies the Google AI Studio API key consumed by this project's gemini-code-review CI job."
  type        = string
  default     = ""
  sensitive   = true
}
