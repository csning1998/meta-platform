
locals {
  # Specifies target repositories whose CI configuration enables AI review components.
  # Repository LaTeX_Documents lacks CI integration and is excluded from key generation.
  ai_review_repos = toset([
    "second-brain",
    "on-premise-agent",
    "app-content-matter",
    "monte-carlo-portfolio-trader",
    "on-premise-gitlab-deployment",
    "template-project",
    "template-project-fullstack",
  ])
}
