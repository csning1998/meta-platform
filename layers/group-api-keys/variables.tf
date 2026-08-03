
variable "gcp_project_id" {
  description = "Specifies the Google Cloud project associated with Generative Language API keys, matching the default project created by Google AI Studio."
  type        = string
  default     = "gen-lang-client-0531142873"
}

variable "claude_api_keys" {
  description = "Maps each repository name to its manually created Claude Console API key. The Anthropic Admin API has no key-creation endpoint, so these values MUST be created in the Console and pasted here; Terraform only stores and distributes them, it does not create them. Every repository in locals.ai_review_repos MUST have a non-empty entry."
  type        = map(string)
  sensitive   = true

  validation {
    condition     = alltrue([for repo in local.ai_review_repos : contains(keys(var.claude_api_keys), repo) && var.claude_api_keys[repo] != ""])
    error_message = "claude_api_keys must contain a non-empty entry for every repository in local.ai_review_repos."
  }
}
