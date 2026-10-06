
output "harbor_registry_mirror" {
  description = "Coordinates for the Talos registry mirrors and the Helm chart source: the Harbor host, the proxy cache project per upstream domain, and the OCI repository of the replicated charts."
  value = {
    host             = local.state.platform_harbor_origin_frontend.harbor_endpoint.fqdn
    mirrors          = { for key, cache in local.proxy_caches : cache.upstream_domain => cache.project_name }
    chart_repository = "oci://${local.state.platform_harbor_origin_frontend.harbor_endpoint.fqdn}/${local.proxy_oci["helm_charts"].name}"
  }
}

output "harbor_projects" {
  description = "Declared Harbor projects partitioned by storage role."
  value = {
    proxy_caches = local.proxy_caches
    proxy_oci    = local.proxy_oci
  }
}

output "harbor_robot_accounts" {
  description = "Harbor robot account identities for automated delivery workflows."
  value = {
    helm_pusher = harbor_robot_account.helm_pusher.full_name
  }
}
