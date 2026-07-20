
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_auth = {
    username = "csning1998"
    password = var.gitlab_token
  }

  new_subgroups = {
    template = {
      name        = "Template"
      description = "Reusable project templates."
    }
    personal = {
      name        = "Personal"
      description = "Personal projects and archives."
    }
  }
}
