
module "service_catalog" {
  source = "../../helpers/service-catalog"

  service_catalog  = var.service_catalog
  network_baseline = var.network_baseline
  domain_suffix    = var.domain_suffix
}
