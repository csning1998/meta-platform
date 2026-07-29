
resource "gitlab_group" "this" {
  name             = "Personal Lab"
  path             = "csning1998-lab"
  description      = "A collection of personal projects and experiments."
  visibility_level = "public"
}
