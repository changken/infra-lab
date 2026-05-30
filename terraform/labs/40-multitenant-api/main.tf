#==============================================================
# 場景：多租戶 SaaS API
#
# 架構（JWT 驗證 + DynamoDB 單表多租戶隔離）：
#
#   POST /items  （帶 Authorization: Bearer <JWT>）
#       │
#       ▼
#   API Gateway HTTP API
#       │ JWT Authorizer（自動驗證 token + 注入 claims）
#       ▼
#   Lambda: api（讀取 claims 中的 tenant_id）
#       │ Query pk = "TENANT#{tenant_id}"
#       ▼
#   DynamoDB（單表設計）
#       pk = "TENANT#{tenant_id}"   ← 租戶隔離在分區鍵
#       sk = "ITEM#{item_id}"       ← 資料排序鍵
#
# DynamoDB 單表多租戶 key 設計：
#   租戶 A 的資料：pk="TENANT#tenant-A", sk="ITEM#uuid"
#   租戶 B 的資料：pk="TENANT#tenant-B", sk="ITEM#uuid"
#   → Query 只能看到自己 pk 的資料，天然隔離
#
# Cognito JWT 流程：
#   1. 管理員建立用戶並設定 custom:tenant_id 屬性
#   2. 用戶透過 initiate-auth 取得 IdToken（含 custom:tenant_id claim）
#   3. API GW JWT Authorizer 驗證 token 合法性（不需 Lambda）
#   4. Lambda 從 event.requestContext.authorizer.jwt.claims 讀取 tenant_id
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6
#==============================================================


# 已完成：打包 Lambda 原始碼
data "archive_file" "api" {
  type        = "zip"
  source_file = "${path.module}/src/api.py"
  output_path = "${path.module}/src/api.zip"
}


#--------------------------------------------------------------
# TODO 1: Cognito User Pool + App Client
#--------------------------------------------------------------
# 文件 (user_pool):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool
# 文件 (app_client): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client
#
# [Cognito User Pool]
#   name = "${var.project}-users"
#
#   password_policy {
#     minimum_length                   = 8
#     require_uppercase                = true
#     require_lowercase                = true
#     require_numbers                  = true
#     require_symbols                  = false
#     temporary_password_validity_days = 7
#   }
#
#   schema {   ← 自訂屬性：tenant_id（注意：schema 的 name 不含 "custom:" 前綴）
#     name                     = "tenant_id"
#     attribute_data_type      = "String"
#     mutable                  = true      ← 允許管理員更新租戶歸屬
#     required                 = false
#     developer_only_attributes = false    ← 讓 App Client 可以讀寫此屬性
#   }
#
#   tags = local.common_tags
#
# [App Client]
#   name          = "${var.project}-client"
#   user_pool_id  = aws_cognito_user_pool.main.id
#   generate_secret = false   ← Public Client（SPA / CLI 工具不能保存 secret）
#
#   explicit_auth_flows = [
#     "ALLOW_USER_PASSWORD_AUTH",    ← 啟用帳號密碼認證（initiate-auth 用）
#     "ALLOW_REFRESH_TOKEN_AUTH",    ← 啟用 Refresh Token
#   ]
#
#   read_attributes  = ["email", "custom:tenant_id"]   ← App 可讀取的屬性
#   write_attributes = ["email", "custom:tenant_id"]   ← App 可寫入的屬性
#
# ⚠️ 注意：
#   - schema 中的 attribute name 是 "tenant_id"
#   - CLI 命令中設定屬性用 "custom:tenant_id"（有 custom: 前綴）
#   - JWT claims 中也是 "custom:tenant_id"（Cognito 自動加前綴）

resource "aws_cognito_user_pool" "main" {
  # TODO
  name = "${var.project}-users"

  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  schema {
    name                     = "tenant_id"
    attribute_data_type      = "String"
    mutable                  = true
    required                 = false
    developer_only_attribute = false
  }

  tags = local.common_tags
}

resource "aws_cognito_user_pool_client" "main" {
  # TODO
  name            = "${var.project}-client"
  user_pool_id    = aws_cognito_user_pool.main.id
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  read_attributes  = ["email", "custom:tenant_id"]
  write_attributes = ["email", "custom:tenant_id"]
}


#--------------------------------------------------------------
# TODO 2: DynamoDB Table（單表多租戶設計）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table
#
# [DynamoDB Table]
#   name         = "${var.project}-items"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "pk"    ← Partition Key = "TENANT#{tenant_id}"
#   range_key    = "sk"    ← Sort Key = "ITEM#{item_id}"
#
#   attribute { name = "pk" type = "S" }
#   attribute { name = "sk" type = "S" }
#
#   tags = local.common_tags
#
# ⚠️ 注意：
#   - 只需宣告 key attributes（pk, sk），非 key 欄位（name, data 等）不需宣告
#   - 單表設計：所有租戶共用一張表，由 pk 前綴做邏輯隔離
#   - 優點：成本低（不需多張表）；代價：需嚴格管理 pk 命名規範

resource "aws_dynamodb_table" "items" {
  # TODO
  name         = "${var.project}-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 3: Lambda IAM Role + Policy
#--------------------------------------------------------------
# 文件 (role):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
# 文件 (attach): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
# 文件 (policy): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
#
# [IAM Role]
#   name = "${var.project}-api-role"
#   assume_role_policy: Principal.Service = "lambda.amazonaws.com"
#
# [Policy Attachment]（CloudWatch Logs 寫入）
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
#
# [Inline Policy]（最小權限：只操作自己的 DynamoDB table）
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect   = "Allow"
#         Action   = ["dynamodb:Query", "dynamodb:PutItem"]
#         Resource = aws_dynamodb_table.items.arn
#       }
#     ]
#   })
#
# ⚠️ 注意：
#   - 只需 Query（讀取租戶資料）+ PutItem（新增資料）
#   - 不需要 Scan（跨租戶查詢），這是多租戶安全的關鍵
#   - Resource 鎖定到特定 table ARN，不用 "*"

resource "aws_iam_role" "api" {
  # TODO
  name = "${var.project}-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "api_basic" {
  # TODO
  role       = aws_iam_role.api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api_dynamodb" {
  # TODO
  name = "${var.project}-api-dynamodb-policy"
  role = aws_iam_role.api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:PutItem"]
        Resource = aws_dynamodb_table.items.arn
      }
    ]
  })
}


#--------------------------------------------------------------
# TODO 4: Lambda Function
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
#
# [Lambda Function]
#   function_name    = "${var.project}-api"
#   role             = aws_iam_role.api.arn
#   handler          = "api.lambda_handler"
#   runtime          = "python3.13"
#   filename         = data.archive_file.api.output_path
#   source_code_hash = data.archive_file.api.output_base64sha256
#   timeout          = 10
#   tags             = local.common_tags
#
#   environment {
#     variables = {
#       TABLE_NAME = aws_dynamodb_table.items.id
#     }
#   }

resource "aws_lambda_function" "api" {
  # TODO
  function_name    = "${var.project}-api"
  role             = aws_iam_role.api.arn
  handler          = "api.lambda_handler"
  runtime          = "python3.13"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.items.id
    }
  }
}


#--------------------------------------------------------------
# TODO 5: API Gateway HTTP API + JWT Authorizer
#--------------------------------------------------------------
# 文件 (api):        https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api
# 文件 (authorizer): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_authorizer
#
# [API Gateway HTTP API]
#   name          = "${var.project}-api"
#   protocol_type = "HTTP"
#   tags          = local.common_tags
#
# [JWT Authorizer]（由 API GW 自動驗證 token，不需要 Lambda）
#   api_id           = aws_apigatewayv2_api.main.id
#   authorizer_type  = "JWT"
#   identity_sources = ["$request.header.Authorization"]   ← 從 Header 取 Bearer token
#   name             = "CognitoJWT"
#
#   jwt_configuration {
#     audience = [aws_cognito_user_pool_client.main.id]  ← 驗證 token 的 aud claim
#     issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
#     # ↑ Cognito JWKS 端點：API GW 從此 URL 取得公鑰來驗證 token 簽章
#   }
#
# ⚠️ 注意：
#   - JWT Authorizer 是 HTTP API 的功能（REST API 用 Cognito Authorizer 設定不同）
#   - issuer URL 格式固定：https://cognito-idp.{region}.amazonaws.com/{user_pool_id}
#   - audience 必須對應 App Client ID，否則 API GW 拒絕 token（403）
#   - API GW 負責驗簽，Lambda 只需信任 requestContext.authorizer.jwt.claims

resource "aws_apigatewayv2_api" "main" {
  # TODO
  name          = "${var.project}-api"
  protocol_type = "HTTP"
  tags          = local.common_tags
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  # TODO
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "CognitoJWT"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.main.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}


#--------------------------------------------------------------
# TODO 6: API GW Integration + Routes + Stage + Lambda Permission
#--------------------------------------------------------------
# 文件 (integration): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration
# 文件 (route):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route
# 文件 (stage):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage
# 文件 (permission):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission
#
# [Lambda Integration]
#   api_id                 = aws_apigatewayv2_api.main.id
#   integration_type       = "AWS_PROXY"
#   integration_uri        = aws_lambda_function.api.invoke_arn
#   payload_format_version = "2.0"   ← HTTP API 使用 2.0（requestContext 結構不同於 1.0）
#
# [Routes]（各自套用 JWT Authorizer）
#   GET  /items:
#     route_key          = "GET /items"
#     authorization_type = "JWT"
#     authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
#     target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
#
#   POST /items:
#     route_key          = "POST /items"
#     （其餘與 GET /items 相同）
#
# [Stage]
#   api_id      = aws_apigatewayv2_api.main.id
#   name        = "$default"       ← HTTP API 的預設 Stage，不需 /stage/ 前綴
#   auto_deploy = true             ← 每次 API 設定改變自動部署，Lab 環境方便
#   tags        = local.common_tags
#
# [Lambda Permission]（允許 API GW 觸發此 Lambda）
#   statement_id  = "AllowAPIGatewayInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.api.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
#   # ↑ 允許此 API 的所有 method + 所有 route 呼叫 Lambda

resource "aws_apigatewayv2_integration" "lambda" {
  # TODO
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_items" {
  # TODO
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /items"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "post_items" {
  # TODO
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /items"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  # TODO
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
  tags        = local.common_tags
}

resource "aws_lambda_permission" "apigw" {
  # TODO
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
