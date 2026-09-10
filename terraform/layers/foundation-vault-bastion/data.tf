
data "terraform_remote_state" "metadata" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base}/foundation-libvirt-resources" })
}

data "local_file" "bastion_vault_ca" {
  filename = local.bastion_vault_ca_cert_path
}

# Secret provisioning MUST persist generated SSH keypairs into Bastion Vault KV storage
# to enforce uniform access control across platform service credentials.
data "local_sensitive_file" "ssh_private_key" {
  for_each = local.state.metadata.ssh_identity_key_paths
  filename = each.value
}

data "local_file" "ssh_public_key" {
  for_each = local.state.metadata.ssh_public_key_paths
  filename = each.value
}
