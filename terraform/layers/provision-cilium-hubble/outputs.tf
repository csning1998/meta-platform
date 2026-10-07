
output "cilium_hubble_fronted_service_vips" {
  description = "VIPs allocated via CiliumLoadBalancerIPPool for platform-foundation's own catalog entries."
  value       = { for key, seg in local.fronted_segments : key => seg.lb_config.vip }
}

output "hubble_ui" {
  description = "Hubble UI access details including ingress hostname, Gateway VIP, and Vault credential path."
  value = {
    hostname    = module.kubernetes_cilium_hubble.hubble_ui.hostname
    gateway_vip = module.kubernetes_cilium_hubble.hubble_ui.gateway_vip
    login_user  = module.kubernetes_cilium_hubble.hubble_ui.login_user
    password_at = "${local.cilium_hubble_external_secrets.kv_mount_path}/${module.kubernetes_cilium_hubble.hubble_ui.kv_path}, field password"
  }
}
