
variable "scripts_root_path" {
  description = "Absolute path to the consuming repository's scripts/ directory, supplied by the calling layer via path.root. A module-relative path.module lookup breaks once this module is fetched from the Terraform Module Registry."
  type        = string
}

variable "config_name" {
  description = "A unique name for this SSH configuration set (e.g., 'kubeadm-cluster')."
  type = object({
    cluster_name    = string
    ssh_config_name = string
  })
}

variable "nodes" {
  description = "A list of node objects to be included in the SSH configs"
  type = list(object({
    key = string
    ip  = string
  }))
}

variable "credentials_vm" {
  description = "Credentials for SSH access to the target VMs."
  type = object({
    username             = string
    ssh_private_key_path = string
  })
  sensitive = true
}

variable "status_trigger" {
  description = "A trigger value that changes when the underlying VMs are recreated."
  type        = any
}
