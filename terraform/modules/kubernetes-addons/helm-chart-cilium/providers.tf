
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.0.2"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.6.1"
    }
  }
}
