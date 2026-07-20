
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_auth = {
    username = "csning1998"
    password = var.gitlab_token
  }

  runner_description = "csning1998-lab-shared-podman-runner"
  runner_tag_list    = ["podman", "local"]
}
