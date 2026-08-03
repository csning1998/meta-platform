
terraform {
  required_version = ">= 1.14.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.40.0"
    }
  }

  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/40-gemini-api-keys"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/40-gemini-api-keys/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/40-gemini-api-keys/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "google" {
  project               = var.gcp_project_id
  user_project_override = true
  billing_project       = var.gcp_project_id
}
