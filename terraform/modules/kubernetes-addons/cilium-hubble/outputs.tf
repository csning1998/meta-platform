
output "hubble_ui" {
  description = "Hubble UI access details including ingress hostname, Gateway VIP, login user, and the KV path of the password."
  value = {
    hostname    = var.hubble_ui_config.hostname
    gateway_vip = var.hubble_ui_config.gateway_vip
    login_user  = var.hubble_ui_config.login_user
    kv_path     = var.hubble_ui_config.kv_path
  }
}
