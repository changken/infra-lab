#==============================================================
# aws-rds-scheduler
#
# 排程（台灣時間 UTC+8）：
#   00:00 CST (16:00 UTC) → stop  所有 available RDS instances
#   08:00 CST (00:00 UTC) → start 所有 stopped  RDS instances
#
# 架構：
#   EventBridge Rule (stop)  → Lambda(ACTION=stop)  → SNS Email
#   EventBridge Rule (start) → Lambda(ACTION=start) → SNS Email
#==============================================================

# ── Lambda zip ─────────────────────────────────────────────

data "archive_file" "scheduler" {
  type        = "zip"
  source_file = "${path.module}/src/scheduler.py"
  output_path = "${path.module}/src/scheduler.zip"
}

# ── SNS ────────────────────────────────────────────────────

resource "aws_sns_topic" "rds_schedule" {
  name = "${var.project}-notify"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.rds_schedule.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── IAM Role ───────────────────────────────────────────────

resource "aws_iam_role" "scheduler_lambda" {
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

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.project}-policy"
  role = aws_iam_role.scheduler_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:StopDBInstance",
          "rds:StartDBInstance",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.rds_schedule.arn
      },
      {
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

# ── Lambda (stop) ──────────────────────────────────────────

resource "aws_lambda_function" "stop" {
  function_name    = "${var.project}-stop"
  filename         = data.archive_file.scheduler.output_path
  source_code_hash = data.archive_file.scheduler.output_base64sha256
  role             = aws_iam_role.scheduler_lambda.arn
  handler          = "scheduler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 60

  environment {
    variables = {
      ACTION        = "stop"
      SNS_TOPIC_ARN = aws_sns_topic.rds_schedule.arn
    }
  }

  tags = local.common_tags
}

# ── Lambda (start) ─────────────────────────────────────────

resource "aws_lambda_function" "start" {
  function_name    = "${var.project}-start"
  filename         = data.archive_file.scheduler.output_path
  source_code_hash = data.archive_file.scheduler.output_base64sha256
  role             = aws_iam_role.scheduler_lambda.arn
  handler          = "scheduler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 60

  environment {
    variables = {
      ACTION        = "start"
      SNS_TOPIC_ARN = aws_sns_topic.rds_schedule.arn
    }
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "stop" {
  name              = "/aws/lambda/${aws_lambda_function.stop.function_name}"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "start" {
  name              = "/aws/lambda/${aws_lambda_function.start.function_name}"
  retention_in_days = 7
  tags              = local.common_tags
}

# ── EventBridge Rules ──────────────────────────────────────

resource "aws_cloudwatch_event_rule" "stop" {
  name                = "${var.project}-stop"
  description         = "Stop RDS at 00:00 CST (16:00 UTC)"
  schedule_expression = var.stop_cron
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_rule" "start" {
  name                = "${var.project}-start"
  description         = "Start RDS at 08:00 CST (00:00 UTC)"
  schedule_expression = var.start_cron
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "stop" {
  rule = aws_cloudwatch_event_rule.stop.name
  arn  = aws_lambda_function.stop.arn
}

resource "aws_cloudwatch_event_target" "start" {
  rule = aws_cloudwatch_event_rule.start.name
  arn  = aws_lambda_function.start.arn
}

resource "aws_lambda_permission" "stop" {
  statement_id  = "AllowEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop.arn
}

resource "aws_lambda_permission" "start" {
  statement_id  = "AllowEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start.arn
}
