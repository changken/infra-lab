locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # OIDC subject 格式：repo:ORG/REPO:ref:refs/heads/BRANCH
  # StringLike 允許使用萬用字元 *
  github_oidc_subject = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
}
