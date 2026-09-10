
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.4.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-cilium-frontend"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-cilium-frontend/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-cilium-frontend/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

provider "vault" {
  address      = data.terraform_remote_state.vault_bootstrapper.outputs.bastion_vault_endpoint
  ca_cert_file = data.terraform_remote_state.vault_bootstrapper.outputs.bastion_vault_listener_ca_cert_path

  auth_login {
    path = "auth/${local.state.spire_parent.spire_oidc_auth_backend_path}/login"
    parameters = {
      role = local.cilium_cluster_name
      jwt  = data.external.spire_jwt.result.jwt
    }
  }
  skip_child_token = true
}

provider "kubernetes" {
  host                   = local.api_server_connection.host
  cluster_ca_certificate = local.api_server_connection.ca_cert
  client_certificate     = local.api_server_connection.client_certificate
  client_key             = local.api_server_connection.client_key
}
