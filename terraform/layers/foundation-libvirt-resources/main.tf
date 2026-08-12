
module "foundation_libvirt_resources" {
  source = "../../modules/kvm-foundation-resources"

  domain_suffix           = var.domain_suffix
  pki_config              = var.global_pki_identity
  network_baseline        = var.network_baseline
  service_catalog         = var.service_catalog
  harbor_registry_proxies = var.harbor_registry_proxies
  vault_kv_namespace      = var.vault_kv_namespace
}
