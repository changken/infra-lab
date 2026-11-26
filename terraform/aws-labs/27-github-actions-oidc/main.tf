#==============================================================
# 學習目標：GitHub Actions + OIDC → AWS IAM Role（零 Access Key）
#
# 核心問題：GitHub Actions 怎麼取得 AWS 權限？
#
# 舊方法（不安全）：
#   在 GitHub Secrets 存 AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY
#   → 長效憑證，洩漏了就完了；需要定期 rotate；違反最小權限很難稽核
#
# 新方法（OIDC）：
#   GitHub Actions → 向 GitHub OIDC Provider 取得短效 JWT Token
#     → 帶著 JWT 向 AWS STS 換取暫時性 Credentials（AssumeRoleWithWebIdentity）
#         → 拿到短效的 Access Key（15 分鐘 ~ 1 小時，用完自動失效）
#
# 新概念：
#   aws_iam_openid_connect_provider → 在 AWS 登記 GitHub 為受信任的 OIDC 身份提供者
#   AssumeRoleWithWebIdentity       → IAM Role 信任政策的特殊 Action
#   token.actions.githubusercontent.com:sub → OIDC Subject，格式：repo:ORG/REPO:ref:refs/heads/BRANCH
#   StringLike Condition            → 允許用萬用字元 * 的字串比對
#
# ⚠️ 安全關鍵：
#   信任政策的 Condition 決定哪些 GitHub repo/branch 可以使用這個 Role。
#   不加 Condition → 任何 GitHub 使用者都能 assume 這個 Role！
#
# 完成順序：1 → 2 → 3
#==============================================================


# 已完成：取得帳號資訊
data "aws_caller_identity" "current" {}


#--------------------------------------------------------------
# TODO 1: GitHub OIDC Identity Provider
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider
#
# 每個 AWS 帳號只需要建立一次 GitHub OIDC Provider。
# 如果你的帳號已有（例如其他 lab 建過），apply 會報衝突 → 用 terraform import 匯入即可。
#
#   url = "https://token.actions.githubusercontent.com"
#
#   client_id_list = ["sts.amazonaws.com"]
#   # GitHub Actions 向 AWS STS 換 credentials，所以 audience 是 sts.amazonaws.com
#
#   thumbprint_list = [
#     "6938fd4d98bab03faadb97b34396831e3780aea1",
#     "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
#   ]
#   # GitHub OIDC 的 TLS 憑證指紋（thumbprint）
#   # AWS 文件說明：https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html
#   # ⚠️ 若 GitHub 更換 TLS 憑證，thumbprint 需要更新，但通常 AWS 會自動信任主要 OIDC 提供者
#
#   tags = local.common_tags

resource "aws_iam_openid_connect_provider" "github" {
  # TODO
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 2: IAM Role（GitHub Actions 可以 Assume 的 Role）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# 信任政策（Trust Policy）是重點，要理解每個欄位：
#
#   name = "${var.project}-github-actions-role"
#   tags = local.common_tags
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Principal = {
#         Federated = aws_iam_openid_connect_provider.github.arn
#         # ← Federated Principal，不是 Service，代表 OIDC 身份提供者
#       }
#       Action = "sts:AssumeRoleWithWebIdentity"
#       # ← 和普通 IAM Role 的 sts:AssumeRole 不同，這是 OIDC 專用的
#
#       Condition = {
#         StringEquals = {
#           "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
#           # ← 確認 audience 是 AWS STS，防止其他服務的 GitHub token 被濫用
#         }
#         StringLike = {
#           "token.actions.githubusercontent.com:sub" = local.github_oidc_subject
#           # ← 核心安全條件：只允許特定 repo + branch
#           # local.github_oidc_subject = "repo:ORG/REPO:ref:refs/heads/BRANCH"
#           # 使用 StringLike 才能用 * 萬用字元（github_branch = "*" 時允許所有分支）
#         }
#       }
#     }]
#   })

resource "aws_iam_role" "github_actions" {
  # TODO
  name = "${var.project}-github-actions-role"
  tags = local.common_tags

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
          "token.actions.githubusercontent.com:sub" = local.github_oidc_subject
        }
      }
    }]
  })
}


#--------------------------------------------------------------
# TODO 3: IAM Policy（Role 可以做什麼）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
#
# 這個 lab 給的權限是「ECR 推送 + ECS 部署」，模擬真實 CI/CD 的最小權限。
# 根據你的實際需求調整即可。
#
#   name = "${var.project}-github-actions-policy"
#   role = aws_iam_role.github_actions.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       # ECR 登入（Resource = "*"，這個 API 設計上不能限縮）
#       {
#         Effect   = "Allow"
#         Action   = ["ecr:GetAuthorizationToken"]
#         Resource = ["*"]
#       },
#       # ECR 推送（限縮到帳號內所有 repo，生產環境建議鎖定特定 repo ARN）
#       {
#         Effect = "Allow"
#         Action = [
#           "ecr:BatchCheckLayerAvailability",
#           "ecr:InitiateLayerUpload",
#           "ecr:UploadLayerPart",
#           "ecr:CompleteLayerUpload",
#           "ecr:PutImage",
#           "ecr:DescribeRepositories"
#         ]
#         Resource = ["arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"]
#       },
#       # ECS 部署（讓 workflow 可以更新 ECS service）
#       {
#         Effect = "Allow"
#         Action = [
#           "ecs:DescribeServices",
#           "ecs:DescribeTaskDefinition",
#           "ecs:RegisterTaskDefinition",
#           "ecs:UpdateService"
#         ]
#         Resource = ["*"]
#       },
#       # IAM PassRole（ECS 部署時需要把 Task Execution Role 傳給 ECS）
#       {
#         Effect   = "Allow"
#         Action   = ["iam:PassRole"]
#         Resource = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"]
#         Condition = {
#           StringEquals = {
#             "iam:PassedToService" = "ecs-tasks.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })

resource "aws_iam_role_policy" "github_actions" {
  # TODO
  name = "${var.project}-github-actions-policy"
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR 登入（Resource = "*"，這個 API 設計上不能限縮）
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      # ECR 推送（限縮到帳號內所有 repo，生產環境建議鎖定特定 repo ARN）
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories"
        ]
        Resource = ["arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"]
      },
      # ECS 部署（讓 workflow 可以更新 ECS service）
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService"
        ]
        Resource = ["*"]
      },
      # IAM PassRole（ECS 部署時需要把 Task Execution Role 傳給 ECS）
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}
