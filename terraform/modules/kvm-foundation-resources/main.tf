
module "service_catalog" {
  source  = var.service_catalog_module.source
  version = var.service_catalog_module.version

  service_catalog  = var.service_catalog
  network_baseline = var.network_baseline
  domain_suffix    = var.domain_suffix
}
