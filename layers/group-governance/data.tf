
data "terraform_remote_state" "group_topology" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base}/10-group-topology" })
}

data "terraform_remote_state" "sonarqube_bootstrap" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base}/15-sonarqube-bootstrap" })
}

# Both arguments resolve through the producing layer's outputs, causing an unapplied
# layers/15-sonarqube-bootstrap to fail here on a missing output rather than a Vault 404.
data "vault_kv_secret_v2" "sonar_token" {
  mount = data.terraform_remote_state.sonarqube_bootstrap.outputs.secret_mount
  name  = data.terraform_remote_state.sonarqube_bootstrap.outputs.secret_name
}
