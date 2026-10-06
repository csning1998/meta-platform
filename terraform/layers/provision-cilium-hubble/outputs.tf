
output "fronted_service_vips" {
  description = "VIPs allocated via CiliumLoadBalancerIPPool for meta-platform's own catalog entries."
  value       = { for key, seg in local.fronted_segments : key => seg.lb_config.vip }
}
