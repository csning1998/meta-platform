
# Vault KV paths follow <project>/<service>/<component>/<leaf>, where components contain leaves only.
# Each leaf designates a single writer layer; consumers read centralized paths rather than composing strings.
# The addon entry serves as a prefix completed by consumers as addon-<name>.
locals {
  foundation_project_code = var.project_code

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

  foundation_kv_paths = {
    for s_name, components in module.foundation_libvirt_resources.vault_path.credential_paths : s_name => {
      for c_name, base in components : c_name => {
        for key, leaf in local.kv_leaf : key => "${base}/${leaf}"
      }
    }
  }
}
