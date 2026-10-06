
variable "ansible_config" {
  description = "Ansible execution configuration."
  type = object({
    root_path         = string
    identity_key_path = optional(string)
    known_hosts_path  = optional(string)
    inventory_file    = string
    verbosity         = optional(number, 4)
  })

  validation {
    condition     = var.ansible_config.root_path != ""
    error_message = "root_path must be a non-empty string."
  }
}

variable "playbook_paths" {
  description = "Absolute paths to the playbooks to run, supplied by the calling module. A module-relative path.module lookup breaks once this module is fetched from the Terraform Module Registry."
  type        = list(string)

  validation {
    condition     = length(var.playbook_paths) > 0
    error_message = "playbook_paths must contain at least one path."
  }
}

variable "inventory_data" {
  description = "Structured inventory data object passed to the template."
  type        = any
}

variable "extra_vars" {
  description = "Map of sensitive/extra variables to pass to Ansible CLI (-e)."
  type        = map(string)
  default     = {}
  # Note: Turn off `sensitive = true` if and only if in development. It must be enabled for production.
  sensitive = true
}

variable "status_trigger" {
  description = "Arbitrary value whose modification triggers re-execution of the provisioner."
  type        = any
}

variable "ansible_tags" {
  description = "Ansible tags to pass via --tags. Empty list runs all tasks."
  type        = list(string)
  default     = []
}

variable "ansible_skip_tags" {
  description = "Ansible tags to pass via --skip-tags."
  type        = list(string)
  default     = []
}
