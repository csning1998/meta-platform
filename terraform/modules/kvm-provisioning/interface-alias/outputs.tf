
# Every set-name and every consumer binding to this interface by name (Keepalived VRRP, policy
# routing) MUST derive the alias only through this module. IFNAMSIZ caps Linux interface names
# at 15 bytes, matched exactly by the "v_" prefix plus 13 characters below.
output "alias" {
  value = "v_${substr(replace(var.name, "-", ""), 0, 13)}"
}
