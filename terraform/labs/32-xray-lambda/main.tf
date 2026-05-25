#==============================================================
# 學習目標：X-Ray + Lambda + API Gateway 分散式追蹤
#
# 核心問題：如何在無伺服器架構中追蹤跨服務的請求鏈路？
#
# X-Ray 三層概念（面試必考）：
#   Trace     → 一次完整的 end-to-end 請求（包含所有 Segment）
#   Segment   → 一個服務的處理時間（API GW 的轉發、Lambda 的執行）
#   Subsegment → Segment 中更細粒度的操作（AWS SDK 呼叫、DB query）
#              → 需要 aws_xray_sdk 手動建立（本 lab 不使用 SDK）
#
# Lambda Tracing Mode（面試必考）：
#   PassThrough → 只傳遞上游送來的 Trace ID，不主動建立 Segment
#   Active      → Lambda runtime 主動送 Segment 至 X-Ray daemon
#              → 需要 AWSXRayDaemonWriteAccess IAM policy
#              → 本 lab 使用 Active mode
#
# API Gateway X-Ray：
#   xray_tracing_enabled = true 設在 aws_api_gateway_stage（非 Method 層）
#   API GW 自動建立自己的 Segment，並注入 X-Amzn-Trace-Id header 給 Lambda
#
# IAM 需要兩個 Policy（面試常考）：
#   AWSLambdaBasicExecutionRole → CloudWatch Logs 寫入
#   AWSXRayDaemonWriteAccess    → 送 trace 至 X-Ray
#   → 少了 XRayDaemonWriteAccess，Lambda trace 不會出現在 X-Ray
#
# 完成順序：1 → 2 → 3 → 4 → 5
#==============================================================


# 已完成：打包 Lambda 原始碼
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/src/handler.zip"
}


#--------------------------------------------------------------
# TODO 1: Lambda IAM Role（含 X-Ray 寫入權限）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# [IAM Role]
#   name = "${var.project}-lambda-role"
#   tags = local.common_tags
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "lambda.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
#
# [Policy Attachment 1：CloudWatch Logs]
#   role       = aws_iam_role.lambda.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
#
# [Policy Attachment 2：X-Ray]
#   role       = aws_iam_role.lambda.name
#   policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
#   # ← 包含 xray:PutTraceSegments、xray:PutTelemetryRecords 等權限

resource "aws_iam_role" "lambda" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  # TODO
}


#--------------------------------------------------------------
# TODO 2: Lambda Function（啟用 X-Ray Active Tracing）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
#
#   function_name    = "${var.project}-handler"
#   runtime          = "python3.12"
#   handler          = "handler.handler"
#   role             = aws_iam_role.lambda.arn
#   filename         = data.archive_file.lambda.output_path
#   source_code_hash = data.archive_file.lambda.output_base64sha256
#   tags             = local.common_tags
#
#   tracing_config {
#     mode = "Active"
#     # PassThrough → 只傳遞 Trace ID，不送 Segment
#     # Active      → 主動送 Segment（本 lab 用這個）
#   }

resource "aws_lambda_function" "handler" {
  # TODO
}


#--------------------------------------------------------------
# TODO 3: API Gateway（REST API + Resource + Method + Integration）
#--------------------------------------------------------------
# 文件 (rest_api):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_rest_api
# 文件 (resource):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_resource
# 文件 (method):     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method
# 文件 (integration):https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration
#
# [REST API]
#   name        = "${var.project}-api"
#   description = "X-Ray Lab API"
#   tags        = local.common_tags
#
# [Resource：/hello]
#   rest_api_id = aws_api_gateway_rest_api.main.id
#   parent_id   = aws_api_gateway_rest_api.main.root_resource_id
#   path_part   = "hello"
#
# [Method：POST /hello]
#   rest_api_id   = aws_api_gateway_rest_api.main.id
#   resource_id   = aws_api_gateway_resource.hello.id
#   http_method   = "POST"
#   authorization = "NONE"
#
# [Integration：Lambda Proxy]
#   rest_api_id             = aws_api_gateway_rest_api.main.id
#   resource_id             = aws_api_gateway_resource.hello.id
#   http_method             = aws_api_gateway_method.post.http_method
#   integration_http_method = "POST"   # ← Lambda invoke 固定用 POST
#   type                    = "AWS_PROXY"
#   uri                     = aws_lambda_function.handler.invoke_arn

resource "aws_api_gateway_rest_api" "main" {
  # TODO
}

resource "aws_api_gateway_resource" "hello" {
  # TODO
}

resource "aws_api_gateway_method" "post" {
  # TODO
}

resource "aws_api_gateway_integration" "lambda" {
  # TODO
}


#--------------------------------------------------------------
# TODO 4: API Gateway Deployment + Stage（啟用 X-Ray）
#--------------------------------------------------------------
# 文件 (deployment): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_deployment
# 文件 (stage):      https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage
#
# [Deployment]
#   rest_api_id = aws_api_gateway_rest_api.main.id
#   triggers = {
#     redeployment = sha1(jsonencode([
#       aws_api_gateway_resource.hello.id,
#       aws_api_gateway_method.post.id,
#       aws_api_gateway_integration.lambda.id,
#     ]))
#   }
#   # ← triggers 確保 method/integration 變更時 Terraform 會重新部署 API
#   lifecycle {
#     create_before_destroy = true
#   }
#
# [Stage：dev]
#   rest_api_id          = aws_api_gateway_rest_api.main.id
#   deployment_id        = aws_api_gateway_deployment.main.id
#   stage_name           = var.environment
#   xray_tracing_enabled = true
#   # ← X-Ray 開關在 Stage 層（不是 Method 或 Resource 層！）
#   tags                 = local.common_tags

resource "aws_api_gateway_deployment" "main" {
  # TODO
}

resource "aws_api_gateway_stage" "dev" {
  # TODO
}


#--------------------------------------------------------------
# TODO 5: Lambda Permission（允許 API Gateway 呼叫 Lambda）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission
#
#   statement_id  = "AllowAPIGatewayInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.handler.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
#   # ← source_arn 限制只有這個 API GW 的任意 Stage/Method 可呼叫
#   #   格式：arn:aws:execute-api:<region>:<account>:<api-id>/<stage>/<method>
#   #   /*/*  = 所有 stage + 所有 method（適合 lab 環境）

resource "aws_lambda_permission" "apigw" {
  # TODO
}
