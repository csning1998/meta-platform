
variable "auth_backend_path" {
  description = "Mount path of the shared vault_jwt_auth_backend that this role attaches to"
  type        = string
}

variable "project_path" {
  description = "GitLab project_path claim value that this role authorizes, e.g. csning1998/gitlab-ci-with-code-reviewer"
  type        = string
}

variable "role_name" {
  description = "Logical name of the JWT auth backend role, unique within auth_backend_path"
  type        = string
}

variable "kv_mount_path" {
  description = "Mount path of the KV v2 secrets engine holding this project's credentials"
  type        = string
}

variable "kv_read_paths" {
  description = "KV v2 data paths, relative to kv_mount_path, that this role may read"
  type        = list(string)

  validation {
    condition     = length(var.kv_read_paths) > 0
    error_message = "kv_read_paths must name at least one path; an empty policy grants no read access."
  }

  validation {
    condition = alltrue([
      for p in var.kv_read_paths : !can(regex("\\*.", p))
    ])
    error_message = "kv_read_paths entries may only use '*' as the final character; Vault ACL globs do not match an interior wildcard."
  }
}

variable "ref_protected" {
  description = "Require the id_token's ref_protected claim to be true, restricting this role to protected branches/tags"
  type        = bool
  default     = true
}

variable "ref_type" {
  description = "GitLab id_token ref_type claim this role is bound to"
  type        = string
  default     = "branch"

  validation {
    condition     = contains(["branch", "tag"], var.ref_type)
    error_message = "ref_type must be 'branch' or 'tag'."
  }
}

variable "token_ttl" {
  description = "Token TTL granted on successful JWT login, matched to typical CI job duration"
  type        = number
  default     = 300
}

variable "token_max_ttl" {
  description = "Maximum token TTL, upper bound on renewal"
  type        = number
  default     = 900
}
