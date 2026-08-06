
module "baseline" {
  source = "../../modules/project-baseline"

  name         = "meta-platform"
  description  = "Shared platform infrastructure and GitLab group governance for the csning1998-lab group."
  visibility   = "public"
  namespace_id = data.terraform_remote_state.foundation_group.outputs.group_id

  claude_api_key = var.claude_api_key
  gemini_api_key = var.gemini_api_key
}
