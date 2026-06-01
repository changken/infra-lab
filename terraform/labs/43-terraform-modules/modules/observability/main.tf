#==============================================================
# Module: observability
# 輸入：project, environment, lambda_function_name,
#       notification_email, tags
# 輸出：sns_topic_arn, lambda_errors_alarm_name
#
# 關鍵學習點：
#   模組接受 lambda_function_name 作為字串變數，
#   而不是直接引用 aws_lambda_function 資源。
#   這是模組邊界（module boundary）的核心設計：
#   不同模組不能直接引用彼此的資源，只能透過 output → variable 傳遞。
#==============================================================

#--------------------------------------------------------------
# TODO 3: SNS Topic + 條件訂閱 + CloudWatch Alarms
#--------------------------------------------------------------
# [SNS Topic]
#   name = "${var.project}-${var.environment}-alarms"
#   tags = var.tags
#
# [Email Subscription]（條件建立）
#   count     = var.notification_email != "" ? 1 : 0
#   topic_arn = aws_sns_topic.alarms.arn
#   protocol  = "email"
#   endpoint  = var.notification_email
#
# [Alarm: Lambda Errors]
#   alarm_name          = "${var.project}-${var.environment}-lambda-errors"
#   namespace           = "AWS/Lambda"
#   metric_name         = "Errors"
#   dimensions          = { FunctionName = var.lambda_function_name }
#   # ↑ 模組邊界：用 var 引用 function name，不是 aws_lambda_function.xxx.function_name
#   period              = 60
#   evaluation_periods  = 1
#   threshold           = 3
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   statistic           = "Sum"
#   treat_missing_data  = "notBreaching"
#   alarm_actions       = [aws_sns_topic.alarms.arn]
#   ok_actions          = [aws_sns_topic.alarms.arn]
#   tags                = var.tags
#
# [Alarm: Lambda Duration P99]
#   alarm_name      = "${var.project}-${var.environment}-lambda-duration"
#   metric_name     = "Duration"
#   dimensions      = { FunctionName = var.lambda_function_name }
#   period          = 300
#   threshold       = 10000   ← 10 秒，超過就告警
#   extended_statistic = "p99"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   treat_missing_data  = "notBreaching"
#   alarm_actions       = [aws_sns_topic.alarms.arn]
#   tags            = var.tags
#
# ⚠️ 注意：
#   - Duration alarm 用 extended_statistic = "p99"（不是 statistic）
#   - extended_statistic 和 statistic 不能同時設定
#   - 模組的 alarm 引用的是 var.lambda_function_name，不是具體資源 ARN

resource "aws_sns_topic" "alarms" {
  # TODO
  name = "${var.project}-${var.environment}-alarms"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  # TODO（記得加 count）
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  # TODO
  alarm_name          = "${var.project}-${var.environment}-lambda-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.lambda_function_name }
  period              = 60
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  # TODO
  alarm_name          = "${var.project}-${var.environment}-lambda-duration"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  dimensions          = { FunctionName = var.lambda_function_name }
  period              = 300
  evaluation_periods  = 2
  threshold           = 10000
  extended_statistic  = "p99"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  tags                = var.tags
}
