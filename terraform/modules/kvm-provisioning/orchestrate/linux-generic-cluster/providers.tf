
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.0"
    }
    sshclient = {
      source = "local/csning1998-lab/sshclient"
    }
  }
}
