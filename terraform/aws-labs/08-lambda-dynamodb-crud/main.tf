#==============================================================
# 學習目標：完整 Serverless CRUD API
#
# 架構：
#   curl / 瀏覽器
#     → API Gateway HTTP API
#         → Lambda（crud.handler）
#             → DynamoDB（items table）
#
# 新概念（比 Lab 07 多的）：
#   aws_iam_role_policy    → 自訂 IAM Policy（給 Lambda DynamoDB 權限）
#   多個 Route             → GET/POST/DELETE 各一條
#   path parameter         → /items/{item_id}（動態路徑）
#   TABLE_NAME env var     → Lambda 讀取 table 名稱的正確做法
#
# API 路由：
#   GET    /items           → 列出全部
#   GET    /items/{item_id} → 取得單筆
#   POST   /items           → 新增
#   DELETE /items/{item_id} → 刪除
#
# 完成順序：1 → 2 → 3 → 4
#==============================================================


# 已完成：zip 打包
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/crud.py"
  output_path = "${path.module}/src/crud.zip"
}

# 已完成：DynamoDB Table（複習 Lab 05，這次用最簡單的 single PK 設計）
resource "aws_dynamodb_table" "items" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "item_id"

  attribute {
    name = "item_id"
    type = "S"
  }

  tags = merge(local.common_tags, { Name = var.table_name })
}

# 已完成：IAM Role（複習 Lab 06/07）
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
# TODO 1: IAM Policy — 給 Lambda DynamoDB 的 CRUD 權限
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
#
# 這次不掛 AWS 內建 Policy，改用 aws_iam_role_policy 寫自訂權限。
# （內建 Policy 太寬，生產環境應精確控制 action 和 resource）
#
# 需要設定：
#   name = "dynamodb-crud"
#   role = aws_iam_role.lambda.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Action = [
#         "dynamodb:GetItem",
#         "dynamodb:PutItem",
#         "dynamodb:DeleteItem",
#         "dynamodb:Scan",
#       ]
#       Resource = [aws_dynamodb_table.items.arn]
#       # ⚠️ Resource 鎖定到這個 table 的 ARN，不是 "*"
#     }]
#   })

resource "aws_iam_role_policy" "lambda_dynamodb" {
  # TODO
  name = "dynamodb-crud"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
      ]
      Resource = [aws_dynamodb_table.items.arn]
    }]
  })
}


#--------------------------------------------------------------
# TODO 2: Lambda Function
#--------------------------------------------------------------
# 跟 Lab 07 相同結構，新增一個環境變數 TABLE_NAME：
#
#   function_name    = var.function_name
#   role             = aws_iam_role.lambda.arn
#   filename         = data.archive_file.lambda_zip.output_path
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256
#   runtime          = "python3.12"
#   handler          = "crud.handler"    # ← 注意：檔名是 crud.py
#
#   environment {
#     variables = {
#       TABLE_NAME  = aws_dynamodb_table.items.name   # ← 新增！Lambda 讀這個變數
#       ENVIRONMENT = var.environment
#     }
#   }
#
#   tags = merge(local.common_tags, { Name = var.function_name })

resource "aws_lambda_function" "crud" {
  # TODO
  function_name = var.function_name
  role = aws_iam_role.lambda.arn
  filename = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime = "python3.12"
  handler = "crud.handler"
  environment{
    variables = {
      TABLE_NAME = aws_dynamodb_table.items.name
      ENVIRONMENT = var.environment
    }
  }
  tags = merge(local.common_tags, { Name = var.function_name })
  depends_on = [aws_iam_role_policy.lambda_dynamodb]  # 確保 IAM Policy 先建立
}


#--------------------------------------------------------------
# TODO 3: API Gateway HTTP API + Stage（複習 Lab 07）
#--------------------------------------------------------------
#
# ── API ──
#   name          = "${var.project}-api"
#   protocol_type = "HTTP"
#   tags          = local.common_tags
#
# ── Stage ──
#   api_id      = aws_apigatewayv2_api.main.id
#   name        = "$default"
#   auto_deploy = true

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
# TODO 4: Integration + Routes + Lambda Permission
#--------------------------------------------------------------
# 文件 (integration): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration
# 文件 (route):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route
#
# ── Integration（只需要一個，所有 route 共用） ──
#   api_id                 = aws_apigatewayv2_api.main.id
#   integration_type       = "AWS_PROXY"
#   integration_uri        = aws_lambda_function.crud.invoke_arn
#   payload_format_version = "2.0"
#
# ── Routes（4 條，注意 path parameter 的格式） ──
#   route_key = "GET /items"
#   route_key = "GET /items/{item_id}"    # {item_id} → event.pathParameters.item_id
#   route_key = "POST /items"
#   route_key = "DELETE /items/{item_id}"
#   target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
#
# ── Lambda Permission ──
#   statement_id  = "AllowAPIGatewayInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.crud.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"

resource "aws_apigatewayv2_integration" "lambda" {
  # TODO
  api_id = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"
  integration_uri = aws_lambda_function.crud.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "list_items" {
  # TODO  route_key = "GET /items"
  api_id = aws_apigatewayv2_api.main.id
  route_key = "GET /items"
  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "get_item" {
  # TODO  route_key = "GET /items/{item_id}"
  api_id = aws_apigatewayv2_api.main.id
  route_key = "GET /items/{item_id}"
  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "create_item" {
  # TODO  route_key = "POST /items"
  api_id = aws_apigatewayv2_api.main.id
  route_key = "POST /items"
  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "delete_item" {
  # TODO  route_key = "DELETE /items/{item_id}"
  api_id = aws_apigatewayv2_api.main.id
  route_key = "DELETE /items/{item_id}"
  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "apigw" {
  # TODO
  statement_id = "AllowAPIGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crud.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
