
data "terraform_remote_state" "foundation_group" {
  backend = "http"
  config  = merge(local._state_auth, { address = "${local._state_base}/00-foundation-group" })
}
