
# Every set-name and every consumer binding to this interface by name (Keepalived VRRP, policy
# routing) MUST derive the alias only through this module. IFNAMSIZ caps Linux interface names
# at 15 bytes, matched exactly by the "v_" prefix (2 bytes) + 8 distinctive alphanumeric characters
# + "_" (1 byte) + 4 hex characters of MD5 digest (total 15 bytes).
output "alias" {
  description = "Linux network interface alias capped at 15 bytes to satisfy IFNAMSIZ."
  value       = "v_${substr(replace(replace(replace(var.name, "platform-foundation-", ""), "meta-platform-", ""), "-", ""), 0, 8)}_${substr(md5(var.name), 0, 4)}"
}
