
# Every Vault KV path of the project follows <project>/<service>/<component>/<leaf>.
# The component level holds leaves only and MUST NOT hold a secret itself.
# Each leaf has one writer layer, and consumers read the paths below instead of composing strings.
# The addon entry is a prefix, which a consumer completes as addon-<name>.
locals {
  project_code = one(distinct([for s in var.service_catalog : s.project_code]))

  kv_leaf = {
    ssh             = "ssh"
    cluster_config  = "cluster-config"
    app             = "app"
    addon           = "addon"
    init            = "init"
    join_token      = "join-token"
    registrar       = "registrar"
    parent_attestor = "parent-attestor"
    robot           = "robot"
  }

  kv_paths = {
    for s_name, components in module.foundation_libvirt_resources.vault_path.credential_paths : s_name => {
      for c_name, base in components : c_name => {
        for key, leaf in local.kv_leaf : key => "${base}/${leaf}"
      }
    }
  }
}
