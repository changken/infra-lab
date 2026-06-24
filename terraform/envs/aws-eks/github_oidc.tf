#==============================================================
# GitHub Actions OIDC — 不用 long-lived AWS Access Key
#
# 流程：
#   GitHub Actions 執行時向 GitHub 取得 OIDC token
#     └── AWS STS 驗證 token（透過 OIDC Provider）
#           └── assume IAM Role → 取得臨時憑證
#                 └── ECR push（無需 IAM User / Access Key）
#
# 安全優勢：
#   - 不存任何 AWS credentials 在 GitHub Secrets
#   - Token 每次 job 自動輪換，TTL 1 小時
#   - Role 的 sub condition 鎖定特定 repo + branch
#==============================================================

# ── GitHub OIDC Provider ─────────────────────────────────────
# 每個 AWS 帳號只需要一個，讓 AWS 信任 GitHub 發行的 OIDC token

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub OIDC 的 thumbprint（固定值，GitHub 官方文件確認）
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.common_tags
}

# ── GitHub Actions IAM Role ──────────────────────────────────

resource "aws_iam_role" "github_actions" {
  name = "${local.name_prefix}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # 鎖定 changken/eks-app repo 的 main branch
          # 改成 "repo:changken/eks-app:*" 可允許所有 branch（較寬鬆）
          "token.actions.githubusercontent.com:sub" = "repo:changken/eks-app:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = local.common_tags
}

# ── IAM Policy：只允許 ECR push 到指定 repository ───────────

resource "aws_iam_policy" "github_actions_ecr" {
  name        = "${local.name_prefix}-github-actions-ecr"
  description = "GitHub Actions: ECR push for eks-app CI/CD"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR 登入（GetAuthorizationToken 無法限制 resource）
      {
        Sid      = "AllowECRLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      # ECR push：只允許 infra-lab-dev-app repository
      {
        Sid    = "AllowECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = aws_ecr_repository.app.arn
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr.arn
}

# ── Output ───────────────────────────────────────────────────

output "github_actions_role_arn" {
  description = "GitHub Actions Role ARN → 填入 GitHub Secret: AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
