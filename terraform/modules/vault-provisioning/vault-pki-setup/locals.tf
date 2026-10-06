
# Documentation: documentation/architecture/platform-spire-parent-frontend.md Section 1 Item C.
locals {
  pki_api_base_url = "${var.vault_endpoint}/v1/${vault_mount.pki_issuer.path}"

  issuer_key_bearing_issuer_ids = [
    for issuer_id, key_id in data.vault_pki_secret_backend_issuers.pki_issuer_issuers.key_info :
    issuer_id if key_id != ""
  ]
}
