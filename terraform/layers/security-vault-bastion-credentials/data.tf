
data "terraform_remote_state" "vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base_parent_group_governance}/foundation-vault-bastion" }
}

data "terraform_remote_state" "foundation" {
  backend = "http"
  config  = { address = "${local._state_base_meta_platform}/foundation-libvirt-resources" }
}

# Generated SSH keypairs persist into the Bastion Vault KV to give every platform service credential one access control.
data "local_sensitive_file" "ssh_private_key" {
  for_each = local.state.foundation.foundation_ssh.identity_key_paths
  filename = each.value
}

data "local_file" "ssh_public_key" {
  for_each = local.state.foundation.foundation_ssh.public_key_paths
  filename = each.value
}
