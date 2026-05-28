#==============================================================
# Module: serverless-api
# 輸入：project, environment, handler, runtime, timeout,
#       memory_size, environment_variables,
#       source_zip_path, source_code_hash, tags
# 輸出：api_endpoint, function_name, function_arn
#==============================================================

#--------------------------------------------------------------
# TODO 2: Lambda IAM Role + Lambda Function + API Gateway HTTP API
#--------------------------------------------------------------
# [IAM Role]
#   name = "${var.project}-${var.environment}-api-role"
#   assume_role_policy: Principal.Service = "lambda.amazonaws.com"
#
# [Policy Attachment]（CloudWatch Logs 寫入）
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
#
# [Lambda Function]（資源名稱用 "this"，模組內部約定）
#   function_name    = "${var.project}-${var.environment}-api"
#   role             = aws_iam_role.this.arn
#   handler          = var.handler
#   runtime          = var.runtime
#   filename         = var.source_zip_path      ← 從 root 傳入，不是 ${path.module}
#   source_code_hash = var.source_code_hash     ← 用於偵測程式碼變更
#   timeout          = var.timeout
#   memory_size      = var.memory_size
#   tags             = var.tags
#
#   environment {
#     variables = var.environment_variables     ← 若 map 為空，API GW 不會出錯
#   }
#
# [API GW HTTP API]
#   name          = "${var.project}-${var.environment}-api"
#   protocol_type = "HTTP"
#   tags          = var.tags
#
# [Lambda Integration]
#   api_id                 = aws_apigatewayv2_api.this.id
#   integration_type       = "AWS_PROXY"
#   integration_uri        = aws_lambda_function.this.invoke_arn
#   payload_format_version = "2.0"
#
# [Route]（$default 匹配所有未定義路徑）
#   api_id    = aws_apigatewayv2_api.this.id
#   route_key = "$default"
#   target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
#
# [Stage]
#   api_id      = aws_apigatewayv2_api.this.id
#   name        = "$default"
#   auto_deploy = true
#   tags        = var.tags
#
# [Lambda Permission]（允許 API GW 呼叫）
#   statement_id  = "AllowAPIGatewayInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.this.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
#
# ⚠️ 注意：
#   - IAM Role 名稱含 environment，確保同 project 的 dev/prod 不衝突
#   - source_zip_path 是從 root 傳入的路徑（root 的 path.module/src/hello.zip）
#     模組內不能用 ${path.module}，因為 path.module 是模組自己的目錄
#   - 輸出 function_name 和 function_arn，讓 observability 模組引用

resource "aws_iam_role" "this" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "basic" {
  # TODO
}

resource "aws_lambda_function" "this" {
  # TODO

  environment {
    variables = var.environment_variables
  }
}

resource "aws_apigatewayv2_api" "this" {
  # TODO
}

resource "aws_apigatewayv2_integration" "lambda" {
  # TODO
}

resource "aws_apigatewayv2_route" "default" {
  # TODO
}

resource "aws_apigatewayv2_stage" "default" {
  # TODO
}

resource "aws_lambda_permission" "apigw" {
  # TODO
}
