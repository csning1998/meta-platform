
variable "gitlab_token" {
  description = "Authenticates the gitlab provider and the Terraform HTTP state backend. Requires the 'api' scope."
  type        = string
  sensitive   = true
}

variable "code_review_bot_token" {
  description = "Populates the CLAUDE_MR_REVIEWER and GEMINI_MR_REVIEWER group variables. Dedicated to the review bot and separate from gitlab_token to limit blast radius on leak."
  type        = string
  sensitive   = true
}

variable "vault_token" {
  description = "Authenticates the vault provider against the self-hosted Vault instance."
  type        = string
  sensitive   = true
}
