
module "foundation_libvirt_resources" {
  source = "../../modules/kvm-foundation-resources"

  domain_suffix           = var.domain_suffix
  pki_config              = var.pki_config
  network_baseline        = var.network_baseline
  service_catalog_module  = var.service_catalog_module
  service_catalog         = var.service_catalog
  harbor_registry_proxies = var.harbor_registry_proxies
}
