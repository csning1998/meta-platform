
data "terraform_remote_state" "foundation_libvirt_resources" {
  backend = "http"
  config  = { address = "${local._state_base_platform_foundation}/foundation-libvirt-resources" }
}

data "terraform_remote_state" "platform_spire_parent" {
  backend = "http"
  config  = { address = "${local._state_base_platform_foundation}/platform-spire-parent-frontend" }
}
