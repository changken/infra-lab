#==============================================================
# 學習目標：Lambda + API Gateway HTTP API
#
# 架構：
#   瀏覽器/curl
#     → API Gateway HTTP API
#         → Integration（橋接）
#             → Lambda Function
#
# 新概念（比 Lab 06 多的）：
#   aws_apigatewayv2_api         → 建立 HTTP API
#   aws_apigatewayv2_stage       → 部署 stage（用 $default）
#   aws_apigatewayv2_integration → 把 API Gateway 接到 Lambda
#   aws_apigatewayv2_route       → 定義路由規則（GET /hello）
#   aws_lambda_permission        → 允許 API Gateway 呼叫 Lambda
#
# 完成順序：1 → 2 → 3 → 4
#==============================================================


# 已完成：zip 打包
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/hello.py"
  output_path = "${path.module}/src/hello.zip"
}

# 已完成：IAM Role（跟 Lab 06 一樣，熟悉的模式）
resource "aws_iam_role" "lambda" {
  name = "${var.function_name}-role"
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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


#--------------------------------------------------------------
# TODO 1: Lambda Function
#--------------------------------------------------------------
# 跟 Lab 06 一樣的結構，這次 handler 格式：hello.handler
#
# 需要設定：
#   function_name    = var.function_name
#   role             = aws_iam_role.lambda.arn
#   filename         = data.archive_file.lambda_zip.output_path
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256
#   runtime          = "python3.12"
#   handler          = "hello.handler"
#   environment { variables = { ENVIRONMENT = var.environment } }
#   tags = merge(local.common_tags, { Name = var.function_name })

resource "aws_lambda_function" "hello" {
  # TODO
  function_name = var.function_name
  role = aws_iam_role.lambda.arn
  filename = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime = "python3.12"
  handler = "hello.handler"
  environment{
    variables = {
      ENVIRONMENT = var.environment
    }
  }
  tags = merge(local.common_tags, { Name = var.function_name })
  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}


#--------------------------------------------------------------
# TODO 2: API Gateway HTTP API + Stage
#--------------------------------------------------------------
# 文件 (api):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api
# 文件 (stage): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage
#
# ── API ──
#   name          = "${var.project}-api"
#   protocol_type = "HTTP"    # HTTP API（比 REST API 便宜、設定簡單）
#   tags          = local.common_tags
#
# ── Stage ──
#   api_id      = aws_apigatewayv2_api.main.id
#   name        = "$default"   # $default = 直接掛在根路徑，不需要 /v1 prefix
#   auto_deploy = true         # 每次變更自動部署，省去手動 deploy 步驟

resource "aws_apigatewayv2_api" "main" {
  # TODO
  name = "${var.project}-api"
  protocol_type = "HTTP"
  tags = local.common_tags
}

resource "aws_apigatewayv2_stage" "default" {
  # TODO
  api_id = aws_apigatewayv2_api.main.id
  name = "$default"
  auto_deploy = true
}


#--------------------------------------------------------------
# TODO 3: Integration + Route（把 API 接到 Lambda）
#--------------------------------------------------------------
# 文件 (integration): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration
# 文件 (route):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route
#
# ── Integration（橋接層） ──
#   api_id                 = aws_apigatewayv2_api.main.id
#   integration_type       = "AWS_PROXY"   # Lambda Proxy：把整個 HTTP request 傳給 Lambda
#   integration_uri        = aws_lambda_function.hello.invoke_arn
#   payload_format_version = "2.0"         # 較新的格式，event 結構更清楚
#
# ── Route（路由規則） ──
#   api_id    = aws_apigatewayv2_api.main.id
#   route_key = "GET /hello"   # 格式：「METHOD /path」，用 "ANY /hello" 可接受所有 method
#   target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"

resource "aws_apigatewayv2_integration" "lambda" {
  # TODO
  api_id = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"
  integration_uri = aws_lambda_function.hello.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "hello" {
  # TODO
  api_id = aws_apigatewayv2_api.main.id
  route_key = "GET /hello"
  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}


#--------------------------------------------------------------
# TODO 4: Lambda Permission（允許 API Gateway 觸發 Lambda）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission
#
# Lambda 預設拒絕外部呼叫，要明確授權給 API Gateway：
#
#   statement_id  = "AllowAPIGatewayInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.hello.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
#   #                                                          ↑↑↑↑
#   #   第一個 * = stage，第二個 * = method，允許所有 stage 和 method

resource "aws_lambda_permission" "apigw" {
  # TODO
  statement_id = "AllowAPIGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
