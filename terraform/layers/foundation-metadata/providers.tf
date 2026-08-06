
terraform {
  required_version = ">= 1.14.0"

  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/foundation-metadata"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/foundation-metadata/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/foundation-metadata/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}
