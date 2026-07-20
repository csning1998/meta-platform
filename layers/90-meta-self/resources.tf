
module "baseline" {
  source = "../../modules/project-baseline"

  name         = "csning1998-lab-meta-provision"
  description  = "Group-level Terraform governance for the csning1998-lab GitLab group."
  visibility   = "public"
  namespace_id = data.terraform_remote_state.foundation_group.outputs.group_id
}
