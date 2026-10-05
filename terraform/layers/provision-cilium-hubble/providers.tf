
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.5.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-cilium-hubble"
    lock_address   = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-cilium-hubble/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/84608830/terraform/state/provision-cilium-hubble/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    retry_wait_min = 5
  }
}

# Authenticated as the local Terraform operator of this component through the SPIRE Parent JWT-SVID. The Downstream KV holds the kubeconfig.
provider "vault" {
  alias        = "downstream"
  address      = local.state.security_vault_downstream_tenants.endpoint
  ca_cert_file = local.state.security_vault_downstream_tenants.ca_cert_path

  # The JWT-SVID arrives through TERRAFORM_VAULT_AUTH_JWT from tools/terraform-operator.sh and stays out of the state.
  auth_login_jwt {
    mount = local.downstream_operator.auth_mount
    role  = local.downstream_operator.role_name
  }
  skip_child_token = true
}

provider "kubernetes" {
  host                   = local.api_server_connection.host
  cluster_ca_certificate = local.api_server_connection.ca_cert
  client_certificate     = local.api_server_connection.client_certificate
  client_key             = local.api_server_connection.client_key
}
