#==============================================================
# aws-billing-guard
#
# 架構：
#   AWS Budgets (月消費 > $threshold)
#     → SNS Topic
#         ├── Email 通知
#         └── Lambda (snapshot + delete 所有 available RDS instances)
#
# ⚠️  AWS Budgets 使用 us-east-1 endpoint，SNS topic 必須在同一 region
#==============================================================

# ── Lambda zip ─────────────────────────────────────────────

data "archive_file" "guard" {
  type        = "zip"
  source_file = "${path.module}/src/guard.py"
  output_path = "${path.module}/src/guard.zip"
}

# ── IAM Role for Lambda ────────────────────────────────────

resource "aws_iam_role" "guard_lambda" {
  name = "${var.project}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "guard_rds" {
  name = "${var.project}-rds-policy"
  role = aws_iam_role.guard_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RDSSnapshotAndDelete"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:CreateDBSnapshot",
          "rds:DescribeDBSnapshots",
          "rds:DeleteDBInstance",
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Stop"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances",
        ]
        Resource = "*"
      },
      {
        Sid    = "ELBManage"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DeleteListener",
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ── Lambda Function ────────────────────────────────────────

resource "aws_lambda_function" "guard" {
  function_name    = "${var.project}-rds-guard"
  filename         = data.archive_file.guard.output_path
  source_code_hash = data.archive_file.guard.output_base64sha256
  role             = aws_iam_role.guard_lambda.arn
  handler          = "guard.lambda_handler"
  runtime          = "python3.13"
  timeout          = 900 # 15 分鐘：等 snapshot 完成需要時間

  environment {
    variables = {
      DRY_RUN = tostring(var.dry_run)
    }
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "guard" {
  name              = "/aws/lambda/${aws_lambda_function.guard.function_name}"
  retention_in_days = 7
  tags              = local.common_tags
}

# ── SNS Topic ──────────────────────────────────────────────

resource "aws_sns_topic" "billing_alert" {
  name = "${var.project}-billing-alert"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.billing_alert.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.billing_alert.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.guard.arn
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guard.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.billing_alert.arn
}

# SNS Topic Policy：允許 Budgets 發布訊息
resource "aws_sns_topic_policy" "billing_alert" {
  arn = aws_sns_topic.billing_alert.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowBudgetsPublish"
      Effect = "Allow"
      Principal = {
        Service = "budgets.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = aws_sns_topic.billing_alert.arn
    }]
  })
}

# ── AWS Budget ─────────────────────────────────────────────

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_amount)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100 # 100% of limit = $38
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.billing_alert.arn]
    subscriber_email_addresses = [var.alert_email]
  }
}
