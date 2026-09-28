
module "contexts_local_credential" {
  source  = "gitlab.com/csning1998-lab/contexts-local-credential/gitlab"
  version = "0.3.0"
}

module "provisioner_gitlab_project" {
  source  = "gitlab.com/csning1998-lab/provisioner-gitlab-project/gitlab"
  version = "0.2.0"

  name         = "meta-platform"
  description  = "Shared platform infrastructure and GitLab group governance for the csning1998-lab group."
  visibility   = "public"
  namespace_id = data.terraform_remote_state.group_topology.outputs.subgroup_ids["platform-engineering-lab"]

  only_allow_merge_if_pipeline_succeeds = true
}

module "github_mirror" {
  source  = "gitlab.com/csning1998-lab/provisioner-github-mirror/gitlab"
  version = "~> 0.3.0"

  gitlab_project_id = module.provisioner_gitlab_project.project_id

  github_repository = {
    name  = "meta-platform"
    owner = var.github_owner
  }
}
