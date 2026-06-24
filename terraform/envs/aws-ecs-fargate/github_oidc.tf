#==============================================================
# GitHub Actions OIDC（ECR push + ECS deploy）
#
# 與 EKS lab 的差異：
#   EKS:  只需要 ECR push 權限（ArgoCD 接管部署）
#   ECS:  需要 ECR push + ECS 更新 service/task definition 的權限
#         GitHub Actions 直接觸發 ECS 滾動更新
#
# 最小權限設計：
#   - ECR push 只限定到 infra-lab-dev-app repository
#   - ECS 操作只限定到 infra-lab-dev-cluster 和相關 service
#   - iam:PassRole 只允許 pass task execution role 和 task role
#==============================================================

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.common_tags
}

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
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "github_actions_deploy" {
  name        = "${local.name_prefix}-github-actions-deploy"
  description = "GitHub Actions: ECR push + ECS rolling deploy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
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
      {
        Sid    = "ECSUpdateService"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:ListTaskDefinitions",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "ecs:cluster" = aws_ecs_cluster.main.arn
          }
        }
      },
      {
        # task definition 沒有支援 Condition，單獨列出
        Sid    = "ECSRegisterTaskDef"
        Effect = "Allow"
        Action = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
        Resource = "*"
      },
      {
        Sid    = "PassRoleToECS"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.task_execution.arn,
          aws_iam_role.task.arn,
        ]
      },
      {
        # CodeDeploy Blue/Green 部署（取代 ECS UpdateService 直接部署）
        Sid    = "CodeDeployDeploy"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetApplicationRevision",
        ]
        Resource = [
          aws_codedeploy_app.app.arn,
          "arn:aws:codedeploy:${var.region}:${data.aws_caller_identity.current.account_id}:deploymentgroup:${aws_codedeploy_app.app.name}/${aws_codedeploy_deployment_group.app.deployment_group_name}",
          "arn:aws:codedeploy:${var.region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:*",
        ]
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "github_actions_deploy" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_deploy.arn
}
