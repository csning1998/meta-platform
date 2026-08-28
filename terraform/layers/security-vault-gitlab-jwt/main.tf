
# 1. Mounts the shared JWT authentication backend using SaaS GitLab CI id_tokens as the sole workload identity provider.
resource "vault_jwt_auth_backend" "gitlab" {
  provider           = vault.bastion
  description        = "GitLab CI id_token federation, shared across repositories"
  path               = local.jwt_auth_backend_path
  type               = "jwt"
  oidc_discovery_url = "https://gitlab.com"

  # Defines lease TTL parameters for the authentication backend.
  # max_lease_ttl MUST maintain headroom above role-level token_max_ttl settings to prevent implicit token lifetime truncation.
  tune {
    listing_visibility = "unauth"
    default_lease_ttl  = "5m"
    max_lease_ttl      = "1h"
  }
}

# 2. Configures Vault JWT workload identity federation for gitlab-ci-with-code-reviewer.
#    Authorizes read access to secret paths matching gitlab-ci-with-code-reviewer/*.
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

# 3. Reserved: Shared JWT authentication backend for self-hosted GitLab CI id_token federation.
#    Retained for future self-managed GitLab workload identity integration.
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
