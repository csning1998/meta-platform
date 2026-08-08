
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
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/group-sonarqube"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/group-sonarqube/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/group-sonarqube/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

# Executes on the local operator host using loopback network bindings.
provider "sonarqube" {
  host              = "http://127.0.0.1:9000"
  user              = "admin"
  pass              = ephemeral.vault_kv_secret_v2.sonarqube_admin.data["sonarqube_admin_password"]
  installed_version = "26.7.0.124771"
}

provider "vault" {
  address      = "https://127.0.0.1:8200"
  ca_cert_file = "${path.module}/../../../vault/tls/ca.pem"
  token        = local.vault_token
}
