
terraform {
  required_version = ">= 1.14.0"
  required_providers {
    ansible = {
      source  = "ansible/ansible"
      version = "~> 1.5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.8.0"
    }
  }
}

data "local_file" "base_ansible_cfg" {
  filename = "${path.module}/templates/ansible.cfg.tftpl"
}

# local_file.inventory and local_file.ansible_cfg both reference this single source for the inventory path.
# Two independently computed copies of this string can diverge.
locals {
  inventory_path = "${var.ansible_config.root_path}/${var.ansible_config.inventory_file}"
}

resource "local_file" "inventory" {
  depends_on = [local_file.ansible_cfg]

  content = format(
    "---\n%s\n# Terraform Status Trigger: %s", # Render YAML opening with terraform status tracking code
    yamlencode(var.inventory_data),
    jsonencode(var.status_trigger)
  )
  filename        = local.inventory_path
  file_permission = "0644"

  lifecycle {
    action_trigger {
      events  = [after_create, after_update]
      actions = [action.ansible_playbook_run.run_playbook]
    }
  }
}

resource "local_file" "ansible_cfg" {
  content = replace(
    replace(
      data.local_file.base_ansible_cfg.content,
      "roles_path = ansible/roles",
      "roles_path = ${var.ansible_config.root_path}/roles"
    ),
    "inventory = ansible/inventory.yaml",
    "inventory = ${local.inventory_path}"
  )
  filename = "${path.cwd}/ansible.cfg"
}

action "ansible_playbook_run" "run_playbook" {
  config {
    playbooks               = var.playbook_paths
    inventory_files         = [caller.filename]
    extra_vars              = var.extra_vars
    verbosity               = var.ansible_config.verbosity
    ansible_playbook_binary = "ansible-playbook"
  }
}
