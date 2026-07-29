
locals {
  _state_base = "https://gitlab.com/api/v4/projects/84608830/terraform/state"
  _state_auth = {
    username = "csning1998"
    password = var.gitlab_token
  }
}

locals {
  subgroups = {
    template = {
      name        = "Template"
      description = "Project templates and boilerplate code."
      visibility  = "public"
    }
    personal = {
      name        = "Personal"
      description = "Personal projects and archives."
      visibility  = "public"
    }
    rug = {
      name        = "RUG"
      description = "RUG course assignments and side projects."
      visibility  = "private"
    }
    "fjcu-colab" = {
      name        = "FJCU-colab"
      description = "Collaborative projects and joint research initiatives."
      visibility  = "public"
    }
  }
}
