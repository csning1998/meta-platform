
# The module composes <kv_namespace>/<domain>/<component>, which dirname and basename split from the leaf path.
module "service_identity" {
  source  = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version = "0.1.1"

  for_each  = local.ssh_paths
  providers = { vault = vault.bastion }

  vault_credential_context = {
    kv_namespace = dirname(dirname(each.value))
    domain       = basename(dirname(each.value))
    component    = basename(each.value)
    static = {
      ssh_private_key_b64 = base64encode(data.local_sensitive_file.ssh_private_key[each.key].content)
      ssh_public_key_b64  = base64encode(data.local_file.ssh_public_key[each.key].content)
    }
  }
}

# The VRRP password of the HAProxy cluster outlives the VMs, and the consumer layer only reads the app leaf.
module "haproxy_keepalived_credential" {
  source    = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version   = "0.1.1"
  providers = { vault = vault.bastion }

  vault_credential_context = {
    kv_namespace = dirname(dirname(local.kv_path.haproxy_app))
    domain       = basename(dirname(local.kv_path.haproxy_app))
    component    = basename(local.kv_path.haproxy_app)
    generate = {
      keepalived_auth_pass = { length = 32 }
    }
  }
}

# The Hubble UI login. The password stays readable in the Bastion Vault. External Secrets Operator derives the bcrypt
# htpasswd line inside the cluster. No hash enters a Terraform state.
module "cilium_hubble_credential" {
  source    = "gitlab.com/csning1998-lab/provisioner-vault-credential/gitlab"
  version   = "0.1.1"
  providers = { vault = vault.bastion }

  vault_credential_context = {
    kv_namespace = dirname(dirname(local.kv_path.cilium_hubble_ui))
    domain       = basename(dirname(local.kv_path.cilium_hubble_ui))
    component    = basename(local.kv_path.cilium_hubble_ui)
    generate = {
      password      = { length = 24 }
      cookie_secret = { length = 32 }
    }
  }
}
