
variable "gemini_api_key" {
  description = "Specifies the Google AI Studio API key consumed by this project's gemini-code-review CI job."
  type        = string
  default     = ""
  sensitive   = true
}
