
# 1. Shared JWT Auth Backend, GitLab CI id_tokens as the sole federation source.
resource "vault_jwt_auth_backend" "gitlab" {
  provider           = vault.bastion
  description        = "GitLab CI id_token federation, shared across repositories"
  path               = local.jwt_auth_backend_path
  type               = "jwt"
  oidc_discovery_url = "https://gitlab.com"

  # max_lease_ttl is a ceiling applied to every role's token_max_ttl. It is
  # set well above the current role default (900s) so a future consumer
  # requesting a larger token_max_ttl is not silently clamped by the mount.
  tune {
    listing_visibility = "unauth"
    default_lease_ttl  = "5m"
    max_lease_ttl      = "1h"
  }
}

# 2. Per-repository role, gitlab-ci-with-code-reviewer.
module "gitlab_ci_with_code_reviewer" {
  source = "../../modules/vault-provisioning/vault-jwt-workload-identity-federation"

  providers = {
    vault = vault.bastion
  }

  auth_backend_path = vault_jwt_auth_backend.gitlab.path
  project_path      = "csning1998/gitlab-ci-with-code-reviewer"
  role_name         = "gitlab-ci-with-code-reviewer"
  kv_mount_path     = local.kv_mount_path
  kv_read_paths     = ["gitlab-ci-with-code-reviewer/*"]
}

# Preserved for future work on on-premise-gitlab
# 3. Shared JWT Auth Backend, self-hosted GitLab CI id_tokens as the federation source.
# resource "vault_jwt_auth_backend" "gitlab_instance" {
#   provider           = vault.bastion
#   description        = "On-premise GitLab CI id_token federation, shared across repositories"
#   path               = "gitlab-instance-jwt"
#   type               = "jwt"
#   oidc_discovery_url = "https://gitlab.homelab-infra.dev"
#
#   tune {
#     listing_visibility = "unauth"
#     default_lease_ttl  = "5m"
#     max_lease_ttl      = "1h"
#   }
# }
