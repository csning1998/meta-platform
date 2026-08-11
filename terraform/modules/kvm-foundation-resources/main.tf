
module "service_catalog" {
  source = "../service-catalog"

  service_catalog    = var.service_catalog
  network_baseline   = var.network_baseline
  domain_suffix      = var.domain_suffix
  vault_kv_namespace = var.vault_kv_namespace
}
