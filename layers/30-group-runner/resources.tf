
resource "gitlab_user_runner" "shared" {
  runner_type = "group_type"
  group_id    = data.terraform_remote_state.group_topology.outputs.top_group_id
  description = local.runner_description
  tag_list    = local.runner_tag_list
  locked      = true
}

resource "local_file" "runner_config" {
  filename = "${path.module}/../../runner-config/config.toml"
  content = templatefile("${path.module}/templates/config.toml.tftpl", {
    runner_name  = local.runner_description
    runner_token = gitlab_user_runner.shared.token
  })
  file_permission = "0600"
}
