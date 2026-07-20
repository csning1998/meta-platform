
resource "gitlab_group" "this" {
  name             = "Personal Lab"
  path             = "csning1998-lab"
  visibility_level = "public"
}
