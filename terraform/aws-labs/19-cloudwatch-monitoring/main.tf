#==============================================================
# 學習目標：CloudWatch 監控完整鏈
#
# ⭐ 本 Lab 建立的監控鏈：
#   Lambda 執行 → CloudWatch Logs → Metric Filter（擷取 ERROR）
#                ↓
#           CloudWatch Alarm（偵測錯誤）
#                ↓
#           SNS Topic → Email 通知
#                ↓
#           CloudWatch Dashboard（視覺化）
#
# ⭐ 新概念：
#   1. aws_sns_topic + aws_sns_topic_subscription
#      建立通知管道，alarm 觸發時自動寄信
#
#   2. aws_cloudwatch_metric_alarm
#      監控 AWS 內建 Metric（如 Lambda Errors），條件成立就發 SNS
#      comparison_operator / evaluation_periods / threshold 是三個關鍵參數
#
#   3. aws_cloudwatch_log_metric_filter
#      從 Log 文字中擷取自訂 Metric（pattern 匹配 → metric_transformation 計數）
#
#   4. aws_cloudwatch_dashboard
#      用 jsonencode 定義 Dashboard 的 Widget 佈局與資料來源
#
# ⭐ 費用等級：🟢 安全（CloudWatch alarm $0.10/月，Dashboard $3/月，Lambda 免費）
#   整個 Lab 費用 < $0.01，可以放著不 destroy 觀察幾天也沒關係。
#==============================================================


#--------------------------------------------------------------
# Lambda 函數（已預填）
# 提供受監控的目標：30% 機率產生 ERROR，用來觸發 Alarm 測試
#--------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content  = <<-PYTHON
      import json, logging, random
      logger = logging.getLogger()
      logger.setLevel(logging.INFO)

      def handler(event, context):
          logger.info("Lambda invoked")
          if random.random() < 0.3:
              logger.error("Simulated error occurred")
              raise Exception("Simulated error for CloudWatch alarm testing")
          logger.info("Lambda completed successfully")
          return {"statusCode": 200, "body": "ok"}
    PYTHON
    filename = "main.py"
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project}-function"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_iam_role" "lambda" {
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

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "app" {
  function_name    = "${var.project}-function"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "main.handler"
  runtime          = "python3.12"

  depends_on = [aws_cloudwatch_log_group.lambda]
  tags       = local.common_tags
}


#--------------------------------------------------------------
# TODO 1: SNS Topic（通知頻道）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic
#
# ⭐ SNS Topic 是 CloudWatch Alarm 的通知接收端。
#    Alarm 觸發時，發 SNS → SNS 轉發給訂閱者（Email / Lambda / SQS...）
#
# 需要設定：
#   name = "${var.project}-alerts"
#   tags = local.common_tags

resource "aws_sns_topic" "alerts" {
  # TODO
  name = "${var.project}-alerts"
  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 2: SNS Topic Subscription（Email 訂閱）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription
#
# ⭐ 訂閱 SNS Topic，讓 alarm 通知寄到 Email。
#    apply 後需到信箱點確認連結（AWS 要求驗證），才會真正收到通知。
#
# 需要設定：
#   topic_arn = aws_sns_topic.alerts.arn
#   protocol  = "email"
#   endpoint  = var.alert_email
#
# ⚠️ apply 後檢查信箱，點「Confirm subscription」，否則 alarm 通知不會寄出

resource "aws_sns_topic_subscription" "email" {
  # TODO
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}


#--------------------------------------------------------------
# TODO 3: CloudWatch Metric Alarm（監控 Lambda 錯誤率）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm
#
# ⭐ 監控 AWS/Lambda 內建 Metric（Errors），超過 threshold 就觸發 SNS 通知。
#
# 需要設定：
#   alarm_name          = "${var.project}-lambda-errors"
#   alarm_description   = "Lambda error rate too high"
#
#   namespace           = "AWS/Lambda"    # AWS 內建 Lambda Metrics 的 namespace
#   metric_name         = "Errors"        # 監控的 Metric 名稱
#   dimensions          = { FunctionName = aws_lambda_function.app.function_name }
#
#   statistic           = "Sum"           # 加總（不是 Average）
#   period              = 60              # 每 60 秒評估一次
#   evaluation_periods  = 1              # 連續 1 個 period 超過就觸發
#   comparison_operator = "GreaterThanThreshold"
#   threshold           = 0              # 只要有任何 Error 就告警
#
#   alarm_actions = [aws_sns_topic.alerts.arn]   # 觸發時 → SNS
#   ok_actions    = [aws_sns_topic.alerts.arn]   # 恢復時 → SNS
#   treat_missing_data = "notBreaching"          # 沒資料不算 alarm
#
#   tags = local.common_tags
#
# ⚠️ threshold = 0 表示 Errors > 0 就告警（任何一個錯誤都通知）

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  # TODO
  alarm_name        = "${var.project}-lambda-errors"
  alarm_description = "Lambda error rate too high"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions  = { FunctionName = aws_lambda_function.app.function_name }

  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0

  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"

  tags = local.common_tags

}


#--------------------------------------------------------------
# TODO 4: CloudWatch Log Metric Filter（從 Log 擷取自訂 Metric）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter
#
# ⭐ 從 Lambda 的 Log 中搜尋 ERROR 關鍵字，每次匹配就計數 +1，
#    形成自訂 Metric（可用於建立第二個 Alarm 或放在 Dashboard）。
#
# 需要設定：
#   name           = "${var.project}-error-count"
#   log_group_name = aws_cloudwatch_log_group.lambda.name
#   pattern        = "ERROR"    # 匹配包含 "ERROR" 的 log 行
#
#   metric_transformation {
#     name      = "ErrorCount"
#     namespace = "${var.project}/Custom"   # 自訂 Metric 的 namespace
#     value     = "1"                       # 每次匹配 +1
#   }
#
# ⚠️ pattern 是 CloudWatch Logs 的過濾語法：
#    "ERROR"            → 包含 ERROR 字串的行
#    "?ERROR ?WARN"     → 包含 ERROR 或 WARN
#    { $.level = "ERROR" } → JSON 格式 log 的欄位匹配

resource "aws_cloudwatch_log_metric_filter" "error_count" {
  # TODO
  name           = "${var.project}-error-count"
  log_group_name = aws_cloudwatch_log_group.lambda.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "ErrorCount"
    namespace = "${var.project}/Custom"
    value     = "1"
  }

}


#--------------------------------------------------------------
# TODO 5: CloudWatch Dashboard（視覺化監控面板）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard
#
# ⭐ Dashboard 的主體是一段 JSON（用 jsonencode 產生），定義 Widget 的排列與資料來源。
#    Widget 座標系：x=0~23（寬 24 格），y=0 起，width/height 自由設定。
#
# 需要設定：
#   dashboard_name = var.project
#
#   dashboard_body = jsonencode({
#     widgets = [
#       {
#         type   = "metric"    # 折線圖 Widget
#         x      = 0
#         y      = 0
#         width  = 12
#         height = 6
#         properties = {
#           title  = "Lambda Invocations & Errors"
#           region = var.region
#           stat   = "Sum"
#           period = 60
#           metrics = [
#             ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.app.function_name],
#             ["AWS/Lambda", "Errors",      "FunctionName", aws_lambda_function.app.function_name],
#           ]
#         }
#       },
#       {
#         type   = "alarm"    # Alarm 狀態 Widget
#         x      = 12
#         y      = 0
#         width  = 12
#         height = 6
#         properties = {
#           title  = "Active Alarms"
#           alarms = [aws_cloudwatch_metric_alarm.lambda_errors.arn]
#         }
#       }
#     ]
#   })
#
# ⚠️ metrics 陣列格式：["Namespace", "MetricName", "DimensionKey", "DimensionValue"]

resource "aws_cloudwatch_dashboard" "main" {
  # TODO
  dashboard_name = var.project
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Invocations & Errors"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.app.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.app.function_name],
          ]
        }
      },
      {
        type   = "alarm"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Active Alarms"
          alarms = [aws_cloudwatch_metric_alarm.lambda_errors.arn]
        }
      }
    ]
  })
}
