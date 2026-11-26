#==============================================================
# 場景：可觀測性全棧
#
# 本 lab 圍繞一個刻意設計「有好有壞」的 Lambda API，
# 建立完整的可觀測性基礎設施：
#
#   使用者 → API Gateway → Lambda（4 條路由）
#                │              ├── GET /        → 200 正常回應
#                │              ├── GET /slow    → 睡 2 秒（Duration P99 可見）
#                │              ├── GET /error   → 固定 500（觸發 Alarm）
#                │              └── GET /random  → 30% 500（觀察 Error Rate）
#                │
#                ├── X-Ray Traces（追蹤每次請求）
#                ├── CloudWatch Logs（結構化 JSON → Logs Insights）
#                ├── CloudWatch Alarms（錯誤超標 → SNS 通知）
#                ├── CloudWatch Dashboard（一頁看所有指標）
#                └── Synthetics Canary（每 5 分鐘主動探測）
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6
#==============================================================


# 已完成：Data Sources
data "aws_caller_identity" "current" {}

# 已完成：S3 bucket 唯一名稱後綴
resource "random_id" "suffix" {
  byte_length = 4
}

# 已完成：打包 Lambda 原始碼
data "archive_file" "app" {
  type        = "zip"
  source_file = "${path.module}/src/app.py"
  output_path = "${path.module}/src/app.zip"
}

# 已完成：打包 Synthetics Canary（注意：必須放在 nodejs/node_modules/ 路徑）
data "archive_file" "canary" {
  type        = "zip"
  output_path = "${path.module}/src/canary.zip"
  source {
    content  = file("${path.module}/src/canary/apiCanary.js")
    filename = "nodejs/node_modules/apiCanary.js"
    # ↑ Synthetics Node.js runtime 的固定路徑規範
    # handler = "apiCanary.handler" 對應到此檔案的 exports.handler
  }
}


#--------------------------------------------------------------
# TODO 1: Lambda IAM Role + Lambda Function（啟用 X-Ray 主動追蹤）
#--------------------------------------------------------------
# 文件 (role):     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
# 文件 (lambda):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
# 文件 (log_group): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group
#
# [CloudWatch Log Group]（先建立以設定 retention，否則 Lambda 自動建立但無 retention）
#   name              = "/aws/lambda/${var.project}-app"
#   retention_in_days = 7
#   tags              = local.common_tags
#
# [IAM Role]
#   name = "${var.project}-app-role"
#   assume_role_policy: Principal.Service = "lambda.amazonaws.com"
#
# [Policy Attachments]
#   1. AWSLambdaBasicExecutionRole   ← CloudWatch Logs 寫入
#   2. AWSXRayDaemonWriteAccess      ← X-Ray Trace 上傳（這是 X-Ray 的關鍵）
#      arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
#
# [Lambda Function]
#   function_name    = "${var.project}-app"
#   role             = aws_iam_role.app.arn
#   handler          = "app.lambda_handler"
#   runtime          = "python3.13"
#   filename         = data.archive_file.app.output_path
#   source_code_hash = data.archive_file.app.output_base64sha256
#   timeout          = 10
#   tags             = local.common_tags
#
#   tracing_config {
#     mode = "Active"   ← 關鍵：啟用 X-Ray 主動追蹤（每個 invocation 都產生 trace）
#                         "PassThrough" = 只有上游傳 X-Ray header 才追蹤
#   }
#
#   depends_on = [aws_cloudwatch_log_group.lambda]  ← 確保 log group 先建立
#
# ⚠️ 注意：
#   - tracing_config.mode = "Active" 讓 Lambda 自動追蹤所有 boto3 呼叫
#   - 不需要在程式碼中 import X-Ray SDK（但 SDK 能加入更細粒度的 subsegment）
#   - X-Ray 費用：前 100,000 traces/月免費，之後 $5/1M traces

resource "aws_cloudwatch_log_group" "lambda" {
  # TODO
  name              = "/aws/lambda/${var.project}-app"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_iam_role" "app" {
  # TODO
  name = "${var.project}-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_basic" {
  # TODO
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "app_xray" {
  # TODO
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "app" {
  # TODO
  function_name    = "${var.project}-app"
  role             = aws_iam_role.app.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.13"
  filename         = data.archive_file.app.output_path
  source_code_hash = data.archive_file.app.output_base64sha256
  timeout          = 10
  tags             = local.common_tags

  tracing_config {
    # TODO
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}


#--------------------------------------------------------------
# TODO 2: API Gateway HTTP API + Access Log
#--------------------------------------------------------------
# 文件 (api):         https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api
# 文件 (stage):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage
# 文件 (integration): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration
# 文件 (permission):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission
#
# [CloudWatch Log Group for API GW Access Logs]
#   name              = "/aws/apigateway/${var.project}"
#   retention_in_days = 7
#   tags              = local.common_tags
#
# [API Gateway HTTP API]
#   name          = "${var.project}-api"
#   protocol_type = "HTTP"
#   tags          = local.common_tags
#
# [Lambda Integration]
#   api_id                 = aws_apigatewayv2_api.main.id
#   integration_type       = "AWS_PROXY"
#   integration_uri        = aws_lambda_function.app.invoke_arn
#   payload_format_version = "2.0"
#
# [Route]（$default 匹配所有路徑，適合 demo API）
#   route_key = "$default"
#   target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
#
# [Stage]
#   name        = "$default"
#   auto_deploy = true
#   tags        = local.common_tags
#
#   access_log_settings {
#     destination_arn = aws_cloudwatch_log_group.apigw.arn
#     format = jsonencode({
#       requestId      = "$context.requestId"
#       requestTime    = "$context.requestTime"
#       httpMethod     = "$context.httpMethod"
#       routeKey       = "$context.routeKey"
#       status         = "$context.status"
#       responseLength = "$context.responseLength"
#       integrationError = "$context.integrationErrorMessage"
#     })
#   }
#
# [Lambda Permission]
#   statement_id  = "AllowAPIGatewayInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.app.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
#
# ⚠️ 注意：
#   - HTTP API access logs 由 AWS 用 Service-Linked Role 寫入 CloudWatch，不需設定 aws_api_gateway_account
#   - REST API 則需要設定 aws_api_gateway_account（面試常考差異）

resource "aws_cloudwatch_log_group" "apigw" {
  # TODO
  name              = "/aws/apigateway/${var.project}"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_apigatewayv2_api" "main" {
  # TODO
  name          = "${var.project}-api"
  protocol_type = "HTTP"
  tags          = local.common_tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  # TODO
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.app.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  # TODO
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  # TODO
  name        = "$default"
  api_id      = aws_apigatewayv2_api.main.id
  auto_deploy = true
  tags        = local.common_tags

  access_log_settings {
    # TODO
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_lambda_permission" "apigw" {
  # TODO
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}


#--------------------------------------------------------------
# TODO 3: SNS Topic + CloudWatch Alarms
#--------------------------------------------------------------
# 文件 (topic):        https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic
# 文件 (subscription): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription
# 文件 (alarm):        https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm
#
# [SNS Topic]
#   name = "${var.project}-alarms"
#   tags = local.common_tags
#
# [Email Subscription]（條件建立：只有 notification_email 非空才建立）
#   count     = var.notification_email != "" ? 1 : 0
#   topic_arn = aws_sns_topic.alarms.arn
#   protocol  = "email"
#   endpoint  = var.notification_email
#
# [Alarm 1: Lambda Error Count]
#   alarm_name          = "${var.project}-lambda-errors"
#   namespace           = "AWS/Lambda"
#   metric_name         = "Errors"
#   dimensions          = { FunctionName = aws_lambda_function.app.function_name }
#   period              = 60
#   evaluation_periods  = 1
#   threshold           = 3          ← 1 分鐘內超過 3 次 error 就告警
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   statistic           = "Sum"
#   treat_missing_data  = "notBreaching"  ← 沒有資料視為正常（非「missing data = breaching」）
#   alarm_actions       = [aws_sns_topic.alarms.arn]
#   ok_actions          = [aws_sns_topic.alarms.arn]
#   tags                = local.common_tags
#
# [Alarm 2: API GW 5XX Error Rate]
#   alarm_name  = "${var.project}-apigw-5xx"
#   namespace   = "AWS/ApiGateway"
#   metric_name = "5XXError"
#   dimensions  = { ApiId = aws_apigatewayv2_api.main.id }
#   period      = 60
#   threshold   = 5
#   statistic   = "Sum"
#
# ⚠️ 注意：
#   - treat_missing_data = "notBreaching" 避免 Lambda 長時間無流量時誤報
#   - ok_actions 讓告警恢復時也發通知（不然你只知道壞了，不知道好了）
#   - count = 0 時 Terraform 不建立 SNS subscription，避免 email 驗證步驟阻塞 apply

resource "aws_sns_topic" "alarms" {
  # TODO
  name = "${var.project}-alarms"
  tags = local.common_tags
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
  alarm_name  = "${var.project}-lambda-errors"
  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.app.function_name
  }
  period              = 60
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  # TODO
  alarm_name          = "${var.project}-apigw-5xx"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5XXError"
  dimensions          = { ApiId = aws_apigatewayv2_api.main.id }
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = local.common_tags
}


#--------------------------------------------------------------
# TODO 4: CloudWatch Log Metric Filter + Custom Alarm
#--------------------------------------------------------------
# 文件 (filter): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter
#
# Log Metric Filter 的用途：
#   把 CloudWatch Logs 中的特定 pattern 轉成 CloudWatch Metric，
#   讓你可以對 Log 內容設定 Alarm（不只能 alarm 在 CloudWatch 原生指標上）
#
# [Log Metric Filter]（計算 Lambda log 中出現 ERROR 的次數）
#   name           = "${var.project}-error-count"
#   log_group_name = aws_cloudwatch_log_group.lambda.name
#   pattern        = "ERROR"   ← 簡單字串比對；JSON log 可用 { $.level = "ERROR" }
#
#   metric_transformation {
#     name          = "AppErrorCount"
#     namespace     = "ObservabilityLab"    ← 自訂 namespace，與 AWS 內建的分開
#     value         = "1"                  ← 每次 match 計 1
#     default_value = "0"                  ← 沒有 match 時視為 0（避免告警誤報）
#     unit          = "Count"
#   }
#
# [Custom Metric Alarm]
#   alarm_name  = "${var.project}-custom-errors"
#   namespace   = "ObservabilityLab"       ← 與上面的 namespace 對應
#   metric_name = "AppErrorCount"          ← 與上面的 name 對應
#   period      = 60
#   threshold   = 5
#   statistic   = "Sum"
#   treat_missing_data = "notBreaching"
#   alarm_actions = [aws_sns_topic.alarms.arn]
#   tags = local.common_tags
#
# ⚠️ 注意：
#   - Log Metric Filter 只計算 filter 建立之後的新 log（歷史 log 不回算）
#   - 自訂 namespace 可以在 CloudWatch Console 的 "Custom Namespaces" 下找到
#   - pattern = "ERROR" 比 { $.level = "ERROR" } 簡單但不精確（任何含 ERROR 字串的行都匹配）

resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  # TODO
  name           = "${var.project}-error-count"
  log_group_name = aws_cloudwatch_log_group.lambda.name
  pattern        = "ERROR"

  metric_transformation {
    name          = "AppErrorCount"
    namespace     = "ObservabilityLab"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "custom_errors" {
  # TODO
  alarm_name          = "${var.project}-custom-errors"
  namespace           = "ObservabilityLab"
  metric_name         = "AppErrorCount"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  tags                = local.common_tags
}


#--------------------------------------------------------------
# TODO 5: CloudWatch Dashboard
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard
#
# [CloudWatch Dashboard]
#   dashboard_name = "${var.project}-dashboard"
#   dashboard_body = jsonencode({   ← 用 jsonencode 可以直接引用 Terraform 資源值
#     widgets = [
#       {
#         type   = "metric"
#         x = 0; y = 0; width = 12; height = 6
#         properties = {
#           title  = "Lambda Invocations & Errors"
#           region = var.region
#           metrics = [
#             ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.app.function_name],
#             ["AWS/Lambda", "Errors",      "FunctionName", aws_lambda_function.app.function_name,
#               { "color" = "#d62728", "yAxis" = "right" }]
#           ]
#           period = 60
#           stat   = "Sum"
#           view   = "timeSeries"
#         }
#       },
#       {
#         type   = "metric"
#         x = 12; y = 0; width = 12; height = 6
#         properties = {
#           title  = "Lambda Duration P99"
#           region = var.region
#           metrics = [
#             ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.app.function_name,
#               { "stat" = "p99" }]
#           ]
#           period = 60
#           view   = "timeSeries"
#         }
#       },
#       {
#         type   = "metric"
#         x = 0; y = 6; width = 12; height = 6
#         properties = {
#           title  = "API Gateway Requests & 5XX"
#           region = var.region
#           metrics = [
#             ["AWS/ApiGateway", "Count",    "ApiId", aws_apigatewayv2_api.main.id],
#             ["AWS/ApiGateway", "5XXError", "ApiId", aws_apigatewayv2_api.main.id,
#               { "color" = "#d62728" }]
#           ]
#           period = 60
#           stat   = "Sum"
#           view   = "timeSeries"
#         }
#       },
#       {
#         type   = "metric"
#         x = 12; y = 6; width = 12; height = 6
#         properties = {
#           title  = "Custom Log Error Count"
#           region = var.region
#           metrics = [
#             ["ObservabilityLab", "AppErrorCount"]
#           ]
#           period = 60
#           stat   = "Sum"
#           view   = "timeSeries"
#         }
#       }
#     ]
#   })
#
# ⚠️ 注意：
#   - jsonencode 讓 widget 裡的值（如 function_name, api id）直接引用 Terraform 資源
#   - 若用 raw JSON string（heredoc），引用資源值需要用 ${} 插值，較易出錯
#   - Dashboard 費用：$3/month/dashboard，2 小時 lab ≈ $0.008

resource "aws_cloudwatch_dashboard" "main" {
  # TODO
  dashboard_name = "${var.project}-dashboard"
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
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.app.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.app.function_name,
            { "color" = "#d62728", "yAxis" = "right" }]
          ]
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Duration P99"
          region = var.region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.app.function_name,
            { "stat" = "p99" }]
          ]
          period = 60
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway Requests & 5XX"
          region = var.region
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.main.id],
            ["AWS/ApiGateway", "5XXError", "ApiId", aws_apigatewayv2_api.main.id,
            { "color" = "#d62728" }]
          ]
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Custom Log Error Count"
          region = var.region
          metrics = [
            ["ObservabilityLab", "AppErrorCount"]
          ]
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
        }
      }
    ]
  })
}


#--------------------------------------------------------------
# TODO 6: Synthetics Canary（主動探測 API 健康狀態）
#--------------------------------------------------------------
# 文件 (canary):    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/synthetics_canary
# 文件 (s3_bucket): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
#
# [S3 Bucket for Canary Artifacts]（存放 canary 執行截圖、HAR 檔、log）
#   bucket        = "${var.project}-canary-${random_id.suffix.hex}"
#   force_destroy = true
#   tags          = local.common_tags
#
# [S3 Public Access Block]
#   block_public_acls = block_public_policy = ignore_public_acls = restrict_public_buckets = true
#
# [Canary IAM Role]（Lambda 的角色，因為 Synthetics 實際上是用 Lambda 執行 canary）
#   name = "${var.project}-canary-role"
#   assume_role_policy: Principal.Service = "lambda.amazonaws.com"
#
# [Canary IAM Inline Policy]
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       { Effect = "Allow"
#         Action = ["s3:PutObject", "s3:GetBucketLocation"]
#         Resource = [aws_s3_bucket.canary.arn, "${aws_s3_bucket.canary.arn}/*"] },
#       { Effect = "Allow"
#         Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
#         Resource = "arn:aws:logs:*:*:*" },
#       { Effect = "Allow"
#         Action = ["cloudwatch:PutMetricData"]
#         Resource = "*" }
#     ]
#   })
#
# [Synthetics Canary]
#   name                 = "${var.project}-heartbeat"
#   artifact_s3_location = "s3://${aws_s3_bucket.canary.id}/artifacts/"
#   execution_role_arn   = aws_iam_role.canary.arn
#   handler              = "apiCanary.handler"     ← 對應 nodejs/node_modules/apiCanary.js
#   zip_file             = filebase64(data.archive_file.canary.output_path)
#   runtime_version      = "syn-nodejs-puppeteer-9.1"
#   start_canary         = true                    ← apply 後立刻開始執行
#   tags                 = local.common_tags
#
#   schedule {
#     expression = "rate(5 minutes)"   ← 每 5 分鐘探測一次
#   }
#
#   run_config {
#     timeout_in_seconds = 60
#     environment_variables = {
#       API_URL = aws_apigatewayv2_stage.default.invoke_url   ← 動態傳入 API endpoint
#     }
#   }
#
# ⚠️ 注意：
#   - Synthetics Canary 的執行環境是 Lambda，所以 IAM Role 的 Trust Policy 用 lambda.amazonaws.com
#   - zip_file 裡的路徑必須是 nodejs/node_modules/{handler_file}.js
#   - 費用：$0.0012/run × 12 runs/hr × 2hr ≈ $0.03，記得 destroy

resource "aws_s3_bucket" "canary" {
  # TODO
  bucket        = "${var.project}-canary-${random_id.suffix.hex}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "canary" {
  # TODO
  bucket = aws_s3_bucket.canary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "canary" {
  # TODO
  name = "${var.project}-canary-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "canary" {
  # TODO
  name = "${var.project}-canary-policy"
  role = aws_iam_role.canary.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetBucketLocation"]
      Resource = [aws_s3_bucket.canary.arn, "${aws_s3_bucket.canary.arn}/*"] },
      { Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:*:*:*" },
      { Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
      Resource = "*" }
    ]
  })
}

resource "aws_synthetics_canary" "api_heartbeat" {
  # TODO
  name                 = "${var.project}-api-heartbeat"
  artifact_s3_location = "s3://${aws_s3_bucket.canary.id}/artifacts/"
  execution_role_arn   = aws_iam_role.canary.arn
  handler              = "apiCanary.handler"
  zip_file             = data.archive_file.canary.output_path
  runtime_version      = "syn-nodejs-puppeteer-9.1"
  start_canary         = true
  tags                 = local.common_tags

  schedule {
    # TODO
    expression = "rate(5 minutes)"
  }

  run_config {
    # TODO
    timeout_in_seconds = 60
    environment_variables = {
      API_URL = aws_apigatewayv2_stage.default.invoke_url
    }
  }
}
