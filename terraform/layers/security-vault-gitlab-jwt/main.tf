
# 1. The JWT authentication backend of the GitLab.com CI job provider is owned by parent-group-governance.
#    This layer stops managing the mount without destroying it.
removed {
  from = vault_jwt_auth_backend.gitlab

  lifecycle {
    destroy = false
  }
}

# 1. Configures Vault JWT workload identity federation for gitlab-ci-with-code-reviewer.
#    Authorizes read access to secret paths matching gitlab-ci-with-code-reviewer/*.
module "gitlab_ci_with_code_reviewer" {
  source = "../../modules/vault-provisioning/vault-jwt-workload-identity-federation"

  providers = {
    vault = vault.bastion
  }

  auth_backend_path = local.jwt_auth_backend_path
  project_path      = "csning1998-lab/gitlab-ci-with-code-reviewer"
  role_name         = "gitlab-ci-with-code-reviewer"
  kv_mount_path     = local.kv_mount_path
  kv_read_paths     = ["gitlab-ci-with-code-reviewer/*"]
}

# 2. Reserved: Shared JWT authentication backend for self-hosted GitLab CI id_token federation.
#    Retained for future self-managed GitLab workload identity integration.
# resource "vault_jwt_auth_backend" "gitlab_instance" {
#   provider           = vault.bastion
#   description        = "On-premise GitLab CI id_token federation, shared across repositories"
#   path               = "gitlab-instance-ci-job-jwt-provider"
#   type               = "jwt"
#   oidc_discovery_url = "https://gitlab.homelab-infra.dev"
#
#   tune {
#     listing_visibility = "unauth"
#     default_lease_ttl  = "5m"
#     max_lease_ttl      = "1h"
#   }
# }
