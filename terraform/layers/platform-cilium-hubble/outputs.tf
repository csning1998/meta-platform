
output "hubble_ui" {
  description = "Hubble UI access details including ingress hostname, Gateway VIP, and Vault credential path."
  value = {
    hostname    = local.hubble_ui.hostname
    gateway_vip = local.entrypoint.gateway_vip
    login_user  = local.hubble_ui.login_user
    password_at = "secret/${local.hubble_ui.kv_path}, field password"
  }
}
