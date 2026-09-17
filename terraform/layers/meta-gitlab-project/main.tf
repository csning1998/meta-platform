
module "contexts_local_credential" {
  source  = "gitlab.com/csning1998-lab/contexts-local-credential/gitlab"
  version = "0.1.1"
}

module "provisioner_gitlab_project" {
  source  = "gitlab.com/csning1998-lab/provisioner-gitlab-project/gitlab"
  version = "0.1.1"

  name         = "meta-platform"
  description  = "Shared platform infrastructure and GitLab group governance for the csning1998-lab group."
  visibility   = "public"
  namespace_id = data.terraform_remote_state.group_topology.outputs.subgroup_ids["platform-engineering-lab"]

  claude_api_key = data.vault_kv_secret_v2.claude_keys.data["meta-platform"]
  # gemini_api_key = data.vault_kv_secret_v2.gemini_keys.data["meta-platform"] # Temporarily comment out since unused
}
