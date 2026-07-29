
module "baseline" {
  source = "../../modules/project-baseline"

  name         = "csning1998-lab-governance"
  description  = "Meta-provisioning project for the csning1998-lab GitLab group."
  visibility   = "public"
  namespace_id = data.terraform_remote_state.foundation_group.outputs.group_id

  claude_api_key = var.claude_api_key
  gemini_api_key = var.gemini_api_key
}
