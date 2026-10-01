
output "proxy_caches" {
  description = "The Declared Harbor Projects for storing container images."
  value       = local.proxy_caches
}

output "proxy_oci" {
  description = "The Declared Harbor Projects for storing OCI images."
  value       = local.proxy_oci
}

output "service_vip" {
  description = "The virtual IP assigned to the Bootstrap Harbor service from Central LB topology."
  value       = local.state.platform_harbor_origin_frontend.service_vip
}

output "harbor_registry_fqdn" {
  description = "Fully qualified domain name of the Harbor OCI registry."
  value       = local.state.platform_harbor_origin_frontend.harbor_origin_fqdn
}

output "node_exporter_targets" {
  description = "Node Exporter scrape target for the Harbor Origin node."
  value       = local.state.platform_harbor_origin_frontend.node_exporter_targets
}

output "helm_pusher_robot_username" {
  description = "Full name of the Harbor robot account used to push Helm charts."
  value       = harbor_robot_account.helm_pusher.full_name
}
