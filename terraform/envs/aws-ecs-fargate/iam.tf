#==============================================================
# IAM Roles for ECS Fargate
#
# EKS vs ECS IAM 概念對比：
#   EKS IRSA:  Pod → ServiceAccount → IAM Role（細粒度，pod 級別）
#   ECS Fargate: Task 有兩個 Role：
#     1. Task Execution Role：ECS agent 使用，pull image、寫 log
#     2. Task Role：容器本身使用，呼叫 AWS API（類似 IRSA 的 Task Role）
#==============================================================

data "aws_caller_identity" "current" {}

# ── Task Execution Role（ECS Agent 使用）────────────────────
# 負責：pull ECR image、寫 CloudWatch Logs、讀 Secrets Manager

resource "aws_iam_role" "task_execution" {
  name = "${local.name_prefix}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 允許讀取 Secrets Manager（用於 secrets 注入到 task definition）
resource "aws_iam_policy" "task_execution_secrets" {
  name        = "${local.name_prefix}-ecs-task-execution-secrets"
  description = "Allow ECS task execution role to read Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.app_config.arn
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_execution_secrets" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.task_execution_secrets.arn
}

# ── Task Role（容器本身使用，類似 IRSA）─────────────────────
# 你的 app code 呼叫 AWS API 時使用此 Role

resource "aws_iam_role" "task" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# 允許 ECS Exec（可以 exec 進容器 debug，類似 kubectl exec）
resource "aws_iam_policy" "task_exec_command" {
  name        = "${local.name_prefix}-ecs-exec-command"
  description = "Allow ECS Exec (interactive shell into running task)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_exec_command" {
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task_exec_command.arn
}
