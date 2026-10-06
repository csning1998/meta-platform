
# The role name equals the identity string of the service, which the tenant ACL scopes by the owner code prefix.
# The play issues the certificate with the tenant token, hence the private key never enters a Terraform state.
resource "vault_pki_secret_backend_role" "stats" {
  backend = local.bastion_pki_platform.mount_path
  name    = local.haproxy_pki_role_name

  allowed_domains    = local.state.foundation_libvirt_resources.foundation_pki.map[module.terraform_layer_context.primary_context.pki_key].dns_san
  allow_subdomains   = false
  allow_glob_domains = false
  allow_bare_domains = true
  allow_ip_sans      = true
  require_cn         = true
  enforce_hostnames  = true
  allow_any_name     = false

  key_type    = "ec"
  key_bits    = 256
  key_usage   = ["DigitalSignature"]
  server_flag = true
  client_flag = true

  max_ttl = 60 * 60 * 24 * 90 # 90 Days
  ttl     = 60 * 60 * 24 * 90 # 90 Days

  ou = local.state.foundation_libvirt_resources.foundation_pki.map[module.terraform_layer_context.primary_context.pki_key].ou
}
