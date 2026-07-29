
terraform {
  required_version = ">= 1.14.0"
  required_providers {
    sonarqube = {
      source  = "jdamata/sonarqube"
      version = "0.16.21"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
  }

  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/15-sonarqube-bootstrap"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/15-sonarqube-bootstrap/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/15-sonarqube-bootstrap/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

# This provider block executes on the operator's own machine instead of
# inside a CI job container attached to sonarqube-ci-net.
provider "sonarqube" {
  host              = "http://127.0.0.1:9000"
  user              = "admin"
  pass              = var.sonarqube_admin_password
  installed_version = "26.7.0.124771"
}

provider "vault" {
  address      = "https://127.0.0.1:8222"
  ca_cert_file = "${path.module}/../../vault/tls/ca.pem"
  token        = var.vault_token
}
