
data "terraform_remote_state" "group_topology" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base}/10-group-topology" })
}
