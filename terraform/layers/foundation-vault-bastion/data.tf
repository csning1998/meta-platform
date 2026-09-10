
data "terraform_remote_state" "metadata" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base}/foundation-libvirt-resources" })
}

data "local_file" "bastion_vault_ca" {
  filename = local.bastion_vault_ca_cert_path
}
