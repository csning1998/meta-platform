
data "terraform_remote_state" "vault_bastion" {
  backend = "http"
  config  = { address = "${local._state_base}/foundation-vault-bastion" }
}
