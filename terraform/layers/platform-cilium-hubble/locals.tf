# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform           = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_base_parent_group_governance = "https://gitlab.com/api/v4/projects/86417732/terraform/state"
}

locals {
  state = {
    platform_cilium_frontend  = data.terraform_remote_state.platform_cilium_frontend.outputs
    provision_cilium_frontend = data.terraform_remote_state.provision_cilium_frontend.outputs
    foundation_vault_bastion  = data.terraform_remote_state.foundation_vault_bastion.outputs
    platform_spire_parent     = data.terraform_remote_state.platform_spire_parent.outputs
    provision_spire_parent    = data.terraform_remote_state.provision_spire_parent.outputs
  }
}

locals {
  # Workstation operator identity requires read-only KV scope for ephemeral kubeconfig retrieval.
  terraform_operator = local.state.provision_spire_parent.terraform_operator["cilium"]
  project_code       = local.state.platform_cilium_frontend.foundation_vault_path.project_code
}

locals {
  kubeconfig   = yamldecode(base64decode(ephemeral.vault_kv_secret_v2.cilium_frontend.data["content_b64"]))
  cluster_info = local.kubeconfig.clusters[0].cluster
  user_info    = local.kubeconfig.users[0].user

  api_server_connection = {
    host               = local.cluster_info.server
    ca_cert            = base64decode(local.cluster_info["certificate-authority-data"])
    client_certificate = base64decode(local.user_info["client-certificate-data"])
    client_key         = base64decode(local.user_info["client-key-data"])
  }
}

locals {
  entrypoint = local.state.provision_cilium_frontend.hubble_ui_entrypoint

  hubble_ui = {
    login_user  = "hubble"
    proxy_image = "quay.io/oauth2-proxy/oauth2-proxy:v7.15.4"
    proxy_port  = 4180
    proxy_name  = "oauth2-proxy"

    gateway_name  = "hubble-ui"
    gateway_class = "cilium" # In-cluster Cilium agent automatically reconciles the default 'cilium' GatewayClass.
    upstream      = "http://hubble-ui.kube-system.svc.cluster.local:80"
    auth_secret   = "hubble-ui-auth"
    tls_secret    = "hubble-ui-tls"
    secret_mount  = "/etc/oauth2-proxy"
    kv_path       = local.state.platform_cilium_frontend.in_cluster_trust.hubble_ui_kv_path

    # Subdomain matches the Bastion PKI role SAN policy and requires external static DNS resolution.
    hostname = "hubble.${local.state.platform_cilium_frontend.foundation_pki.map["cilium-frontend"].dns_san[0]}"
  }
}
