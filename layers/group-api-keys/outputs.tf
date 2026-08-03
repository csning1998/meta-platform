
output "gemini_api_keys" {
  description = "Maps each repository name to its dedicated Generative Language API key string."
  value       = { for repo, key in google_apikeys_key.gemini : repo => key.key_string }
  sensitive   = true
}

output "claude_api_keys" {
  description = "Maps each repository name to its manually provisioned Claude Console API key."
  value       = var.claude_api_keys
  sensitive   = true
}
