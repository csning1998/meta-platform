
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

variable "slack_review_webhook_url" {
  description = "Populates the SLACK_REVIEW_WEBHOOK_URL group variable consumed by gitlab-ci-with-code-reviewer. Posts AI review notifications to the #gitlab-code-review Slack channel."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.slack_review_webhook_url == "" || can(regex("^https://hooks\\.slack\\.com/", var.slack_review_webhook_url))
    error_message = "slack_review_webhook_url must be empty or a Slack Incoming Webhook URL starting with https://hooks.slack.com/."
  }
}

variable "gemini_api_key" {
  description = "Populates the GEMINI_API_KEY group variable consumed by gitlab-ci-with-code-reviewer's Gemini review job. Value originates from Google AI Studio."
  type        = string
  default     = ""
  sensitive   = true
}

variable "claude_api_key" {
  description = "Populates the CLAUDE_API_KEY group variable consumed by gitlab-ci-with-code-reviewer's Claude review job. Value originates from the Anthropic Console."
  type        = string
  default     = ""
  sensitive   = true
}
