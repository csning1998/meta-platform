
# GitLab HTTP backend base URL. Authentication credentials must be supplied via
# `TF_HTTP_USERNAME` and `TF_HTTP_PASSWORD` environment variables.
locals {
  _state_base_meta_platform = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
}

locals {
  state = {
    security_vault_downstream_tenants = data.terraform_remote_state.security_vault_downstream_tenants.outputs
    security_vault_downstream_pki     = data.terraform_remote_state.security_vault_downstream_pki.outputs
    platform_harbor_origin_frontend   = data.terraform_remote_state.platform_harbor_origin_frontend.outputs
    provision_keycloak_oidc           = data.terraform_remote_state.provision_keycloak_oidc.outputs
    provision_spire_child             = data.terraform_remote_state.provision_spire_child.outputs
  }
}

locals {
  sys_vault_endpoint = "https://${local.state.security_vault_downstream_tenants.service_vip}:443"
}

locals {
  kv_paths = local.state.security_vault_downstream_tenants.foundation_vault_path.kv_paths
}

locals {
  ansible_extra_vars = {
    harbor_robot_user      = harbor_robot_account.helm_pusher.full_name
    harbor_registry        = local.state.platform_harbor_origin_frontend.harbor_origin_fqdn
    harbor_project         = local.proxy_oci["helm_charts"].name
    vault_endpoint         = local.sys_vault_endpoint
    vault_ca_cert_path     = local.state.security_vault_downstream_tenants.ca_cert_path
    vault_operator_wrapper = local.state.provision_spire_child.terraform_operator_downstream["harbor-origin"].wrapper_name
    vault_operator_role    = local.state.security_vault_downstream_tenants.tenant_operator.role_name
    vault_operator_mount   = local.state.security_vault_downstream_tenants.tenant_operator.auth_mount
    harbor_robot_kv_path   = local.kv_paths["harbor-origin"]["frontend"].robot
  }

  ansible_config = {
    root_path       = abspath("${path.root}/../../../ansible")
    ssh_config_path = local.state.platform_harbor_origin_frontend.ssh_config_file_path
    inventory_file  = "inventory-provision-harbor-origin-frontend.yaml"
  }

  # Transforms the infra-* inventory structure into a dedicated group for this layer's business logic
  inventory_data = {
    all = {
      children = {
        harbor_origin_oci = {
          hosts = {
            for k, v in local.state.platform_harbor_origin_frontend.ansible_inventory.data.all.children.primary.hosts : k => merge(v, {
              node_role = "harbor_origin_oci"
            })
          }
        }
      }
    }
  }
}

locals {
  proxy_oci = {
    helm_charts = {
      name = "helm-charts"
    }
  }
}

locals {
  proxy_caches = {
    docker_hub = {
      registry_name = "hub.docker.com"
      endpoint_url  = "https://hub.docker.com"
      provider_name = "docker-hub"
      project_name  = "docker-proxy"
    }
    k8s_io = {
      registry_name = "registry.k8s.io"
      endpoint_url  = "https://registry.k8s.io"
      provider_name = "docker-registry"
      project_name  = "k8s-proxy"
    }
    quay_io = {
      registry_name = "quay.io"
      endpoint_url  = "https://quay.io"
      provider_name = "docker-registry"
      project_name  = "quay-proxy"
    }
    gitlab_com = {
      registry_name = "registry.gitlab.com"
      endpoint_url  = "https://registry.gitlab.com"
      provider_name = "docker-registry"
      project_name  = "gitlab-proxy"
    }
    gcr_io = {
      registry_name = "gcr.io"
      endpoint_url  = "https://gcr.io"
      provider_name = "docker-registry"
      project_name  = "gcr-proxy"
    }
    ghcr_io = {
      registry_name = "ghcr.io"
      endpoint_url  = "https://ghcr.io"
      provider_name = "docker-registry"
      project_name  = "ghcr-proxy"
    }
  }
}
