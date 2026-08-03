
resource "gitlab_group" "subgroups" {
  for_each = local.subgroups

  name             = each.value.name
  path             = each.key
  description      = each.value.description
  parent_id        = data.terraform_remote_state.foundation_group.outputs.group_id
  visibility_level = each.value.visibility
}
