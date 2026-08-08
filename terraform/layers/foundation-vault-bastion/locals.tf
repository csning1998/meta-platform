
# GitLab HTTP backend credentials (read at plan time from gitignored file)
locals {
  _gl_creds   = jsondecode(file(pathexpand("~/.terraform.d/credentials.tfrc.json")))
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_auth = {
    username = "oauth2"
    password = local._gl_creds.credentials["gitlab.com"].token
  }
}

locals {
  state = {
    metadata = data.terraform_remote_state.metadata.outputs
  }
}

locals {
  bootstrap_leaf_extra_domains = {
    "vault-frontend"      = ["vault", "localhost"]
    "central-lb-frontend" = []
  }

  bootstrap_leaf_roles = {
    for name, extras in local.bootstrap_leaf_extra_domains : name => {
      allowed_domains = concat(local.state.metadata.global_pki_map[name].dns_san, extras)
      ou              = local.state.metadata.global_pki_map[name].ou
    }
  }
}

check "vault_ca_cert_present" {
  assert {
    condition     = fileexists("${path.module}/../../../vault/tls/ca.pem")
    error_message = "Vault CA certificate file missing at vault/tls/ca.pem referenced by providers.tf ca_cert_file."
  }
}
