
terraform {
  required_version = ">= 1.14.0"
  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "19.2.0"
    }
  }

  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/20-group-governance"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/20-group-governance/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/20-group-governance/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "gitlab" {
  token = var.gitlab_token
}
