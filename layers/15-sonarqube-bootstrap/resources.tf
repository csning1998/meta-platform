
# A Vault instance rebuilt from an empty raft store provides no default KV mount.
resource "vault_mount" "kv" {
  path = "secret"
  type = "kv-v2"
}

resource "sonarqube_user_token" "ci_analysis" {
  name = "gitlab-ci-analysis"
  type = "GLOBAL_ANALYSIS_TOKEN"
}

resource "vault_kv_secret_v2" "sonar_token" {
  mount = vault_mount.kv.path
  name  = "sonarqube"
  data_json = jsonencode({
    token = sonarqube_user_token.ci_analysis.token
  })
}
