#==============================================================
# Secrets Manager Rotation — self-generated chat-api-key
#
# 流程：
#   Secrets Manager 定時觸發 Lambda（every 30 days）
#     └── createSecret  → secrets.token_hex(16) → AWSPENDING
#     └── setSecret     → no-op（自產 key）
#     └── testSecret    → 驗證 AWSPENDING JSON 格式
#     └── finishSecret  → AWSPENDING 升格為 AWSCURRENT
#           └── ESO refreshInterval 到期 → 同步到 K8s Secret
#==============================================================

# ── 打包 Lambda 原始碼 ────────────────────────────────────────

data "archive_file" "rotate_secret" {
  type        = "zip"
  source_file = "${path.module}/lambda/rotate_secret.py"
  output_path = "${path.module}/lambda/rotate_secret.zip"
}

# ── Lambda IAM Role ───────────────────────────────────────────

resource "aws_iam_role" "rotate_secret_lambda" {
  name = "${local.name_prefix}-rotate-secret-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "rotate_secret_lambda" {
  name = "${local.name_prefix}-rotate-secret-lambda"
  role = aws_iam_role.rotate_secret_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs
      {
        Sid      = "AllowLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-rotate-secret:*"
      },
      # Secrets Manager rotation 必要權限（只限 custom-app secret）
      {
        Sid    = "AllowRotation"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecretVersionStage",
        ]
        Resource = aws_secretsmanager_secret.custom_app.arn
      },
    ]
  })
}

# ── Lambda Function ───────────────────────────────────────────

resource "aws_lambda_function" "rotate_secret" {
  function_name    = "${local.name_prefix}-rotate-secret"
  role             = aws_iam_role.rotate_secret_lambda.arn
  runtime          = "python3.12"
  handler          = "rotate_secret.lambda_handler"
  filename         = data.archive_file.rotate_secret.output_path
  source_code_hash = data.archive_file.rotate_secret.output_base64sha256
  timeout          = 30

  tags = local.common_tags
}

# ── 允許 Secrets Manager 觸發 Lambda ─────────────────────────

resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotate_secret.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.custom_app.arn
}

# ── Rotation Schedule ─────────────────────────────────────────

resource "aws_secretsmanager_secret_rotation" "custom_app" {
  secret_id           = aws_secretsmanager_secret.custom_app.id
  rotation_lambda_arn = aws_lambda_function.rotate_secret.arn

  rotation_rules {
    # 每 30 天自動輪換一次
    automatically_after_days = 30
  }
}

# ── Outputs ──────────────────────────────────────────────────

output "rotation_lambda_name" {
  description = "Rotation Lambda function name（手動觸發用）"
  value       = aws_lambda_function.rotate_secret.function_name
}

output "rotation_test_command" {
  description = "手動觸發一次 rotation 的指令"
  value       = "aws secretsmanager rotate-secret --secret-id ${aws_secretsmanager_secret.custom_app.name} --region ${var.region}"
}
