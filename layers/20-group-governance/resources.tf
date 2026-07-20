
resource "gitlab_group_label" "this" {
  for_each = local.group_labels

  group       = data.terraform_remote_state.group_topology.outputs.top_group_id
  name        = each.key
  color       = each.value.color
  description = each.value.description
}

resource "gitlab_group_variable" "review_secret" {
  for_each = local.group_variables_secret

  group     = data.terraform_remote_state.group_topology.outputs.top_group_id
  key       = each.key
  value     = each.value
  masked    = true
  hidden    = true
  raw       = true
  protected = false
}

resource "gitlab_group_variable" "slack_review_webhook" {
  group     = data.terraform_remote_state.group_topology.outputs.top_group_id
  key       = "SLACK_REVIEW_WEBHOOK_URL"
  value     = var.slack_review_webhook_url
  masked    = length(var.slack_review_webhook_url) >= 8
  protected = false
}
