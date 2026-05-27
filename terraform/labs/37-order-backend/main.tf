#==============================================================
# 場景：電商訂單後端
#
# 架構（事件驅動，解耦驗證與處理）：
#
#   POST /orders
#        │
#        ▼
#   API Gateway HTTP API
#        │
#        ▼
#   Lambda: validator          ← 驗證欄位，產生 order_id
#        │ sqs:SendMessage
#        ▼
#   SQS Queue (orders)  ←──── DLQ（失敗 3 次後進死信佇列）
#        │ event source mapping
#        ▼
#   Lambda: processor          ← 寫入 DynamoDB，發送 SNS 通知
#        ├── dynamodb:PutItem
#        │        ▼
#        │   DynamoDB (orders table)
#        └── sns:Publish
#                 ▼
#            SNS Topic → Email
#
# 設計決策（ADR 摘要，完整見 README）：
#   1. 驗證與處理拆成兩個 Lambda → SQS 解耦，Validator 失敗不影響 Processor
#   2. SQS DLQ maxReceiveCount=3 → 失敗訂單隔離，不重複消費
#   3. HTTP API GW（v2）非 REST API → 費用更低，設定更簡單
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6 → 7
#==============================================================


# 已完成：打包 Lambda 原始碼（src/ 目錄已預先提供）
data "archive_file" "validator" {
  type        = "zip"
  source_file = "${path.module}/src/validator.py"
  output_path = "${path.module}/src/validator.zip"
}

data "archive_file" "processor" {
  type        = "zip"
  source_file = "${path.module}/src/processor.py"
  output_path = "${path.module}/src/processor.zip"
}


#--------------------------------------------------------------
# TODO 1: DynamoDB Table（訂單資料儲存）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table
#
#   name         = "${var.project}-orders"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "order_id"
#   tags         = local.common_tags
#
#   attribute {
#     name = "order_id"
#     type = "S"
#   }
#
# ⚠️ 注意：attribute block 只需定義 hash_key 用到的欄位
#          processor.py 會寫入 customer_id、items、total_amount 等欄位，
#          但 DynamoDB Schema-less，這些欄位不需要在 attribute block 宣告

resource "aws_dynamodb_table" "orders" {
  # TODO

  attribute {
    # TODO
  }
}


#--------------------------------------------------------------
# TODO 2: SQS Dead Letter Queue + 訂單 Queue
#--------------------------------------------------------------
# 文件 (sqs_queue): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
#
# [DLQ]（死信佇列，先建，因為 Main Queue 的 redrive_policy 需要 DLQ ARN）
#   name = "${var.project}-orders-dlq"
#   tags = local.common_tags
#
# [Main Queue]（訂單佇列）
#   name                       = "${var.project}-orders"
#   visibility_timeout_seconds = 180   # 必須 >= Lambda timeout × 6（Lambda 預設 30s → 180s）
#   tags                       = local.common_tags
#
#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
#     maxReceiveCount     = 3   # 失敗 3 次後移入 DLQ（面試常考：這個值怎麼選？）
#   })
#
# ⚠️ 注意：visibility_timeout_seconds 必須 >= Lambda timeout × 6
#          若太短，Lambda 還在處理時訊息變為可見，同一訊息被重複消費

resource "aws_sqs_queue" "orders_dlq" {
  # TODO
}

resource "aws_sqs_queue" "orders" {
  # TODO
}


#--------------------------------------------------------------
# TODO 3: SNS Topic + Email Subscription（訂單通知）
#--------------------------------------------------------------
# 文件 (topic):        https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic
# 文件 (subscription): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription
#
# [SNS Topic]
#   name = "${var.project}-orders-topic"
#   tags = local.common_tags
#
# [Email Subscription]
#   topic_arn = aws_sns_topic.orders.arn
#   protocol  = "email"
#   endpoint  = var.notification_email
#
# ⚠️ 注意：apply 後立即查收確認信並點擊連結，否則 SNS 不會發送通知

resource "aws_sns_topic" "orders" {
  # TODO
}

resource "aws_sns_topic_subscription" "email" {
  # TODO
}


#--------------------------------------------------------------
# TODO 4: IAM Roles（Validator Lambda + Processor Lambda）
#--------------------------------------------------------------
# 文件 (iam_role):              https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
# 文件 (iam_role_policy):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
# 文件 (iam_role_policy_attach): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
#
# [Validator IAM Role]
#   name = "${var.project}-validator-role"
#   assume_role_policy: Principal.Service = "lambda.amazonaws.com"
#
# [Validator Policy Attachment]（CloudWatch Logs 寫入權限）
#   role       = aws_iam_role.validator.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
#
# [Validator Inline Policy]（只允許送訊息到 orders queue）
#   name   = "sqs-send"
#   role   = aws_iam_role.validator.name
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect   = "Allow"
#       Action   = "sqs:SendMessage"
#       Resource = aws_sqs_queue.orders.arn
#     }]
#   })
#
# [Processor IAM Role]
#   name = "${var.project}-processor-role"
#   assume_role_policy: 同上
#
# [Processor Policy Attachment]（CloudWatch Logs 寫入權限）
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
#
# [Processor Inline Policy]（DynamoDB 寫入 + SNS 發布 + SQS 消費）
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       { Effect = "Allow", Action = ["dynamodb:PutItem", "dynamodb:UpdateItem"],
#         Resource = aws_dynamodb_table.orders.arn },
#       { Effect = "Allow", Action = "sns:Publish",
#         Resource = aws_sns_topic.orders.arn },
#       { Effect = "Allow",
#         Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
#         Resource = aws_sqs_queue.orders.arn }
#     ]
#   })
#
# ⚠️ 注意：Processor 必須有 sqs:ReceiveMessage + sqs:DeleteMessage + sqs:GetQueueAttributes
#          這三個權限是 Lambda Event Source Mapping（TODO 7）正常運作的必要條件

resource "aws_iam_role" "validator" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "validator_basic" {
  # TODO
}

resource "aws_iam_role_policy" "validator_sqs" {
  # TODO
}

resource "aws_iam_role" "processor" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "processor_basic" {
  # TODO
}

resource "aws_iam_role_policy" "processor_permissions" {
  # TODO
}


#--------------------------------------------------------------
# TODO 5: Lambda Functions（Validator + Processor）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
#
# [Validator Lambda]
#   function_name = "${var.project}-validator"
#   role          = aws_iam_role.validator.arn
#   handler       = "validator.lambda_handler"
#   runtime       = "python3.13"
#   filename      = data.archive_file.validator.output_path
#   source_code_hash = data.archive_file.validator.output_base64sha256
#   timeout       = 30
#   tags          = local.common_tags
#
#   environment {
#     variables = {
#       ORDER_QUEUE_URL = aws_sqs_queue.orders.url
#     }
#   }
#
# [Processor Lambda]
#   function_name = "${var.project}-processor"
#   role          = aws_iam_role.processor.arn
#   handler       = "processor.lambda_handler"
#   runtime       = "python3.13"
#   filename      = data.archive_file.processor.output_path
#   source_code_hash = data.archive_file.processor.output_base64sha256
#   timeout       = 30
#   tags          = local.common_tags
#
#   environment {
#     variables = {
#       ORDERS_TABLE  = aws_dynamodb_table.orders.name
#       SNS_TOPIC_ARN = aws_sns_topic.orders.arn
#     }
#   }
#
# ⚠️ 注意：handler 格式為 "{檔名}.{函數名}"，不含 .py 副檔名

resource "aws_lambda_function" "validator" {
  # TODO

  environment {
    variables = {
      # TODO
    }
  }
}

resource "aws_lambda_function" "processor" {
  # TODO

  environment {
    variables = {
      # TODO
    }
  }
}


#--------------------------------------------------------------
# TODO 6: API Gateway HTTP API（POST /orders 入口）
#--------------------------------------------------------------
# 文件 (api):         https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api
# 文件 (integration): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration
# 文件 (route):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route
# 文件 (stage):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage
# 文件 (permission):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission
#
# [API]
#   name          = "${var.project}-api"
#   protocol_type = "HTTP"
#   tags          = local.common_tags
#
# [Integration]（API GW → Validator Lambda）
#   api_id             = aws_apigatewayv2_api.main.id
#   integration_type   = "AWS_PROXY"
#   integration_uri    = aws_lambda_function.validator.invoke_arn
#   payload_format_version = "2.0"
#
# [Route]（只接受 POST /orders）
#   api_id    = aws_apigatewayv2_api.main.id
#   route_key = "POST /orders"
#   target    = "integrations/${aws_apigatewayv2_integration.validator.id}"
#
# [Stage]（$default 自動部署）
#   api_id      = aws_apigatewayv2_api.main.id
#   name        = "$default"
#   auto_deploy = true
#   tags        = local.common_tags
#
# [Lambda Permission]（允許 API GW 呼叫 Validator）
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.validator.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
#
# ⚠️ 注意：source_arn 後綴 /*/*  代表「此 API 的所有 stage / 所有 route」
#          少了此 Permission，API GW 呼叫 Lambda 會回 403

resource "aws_apigatewayv2_api" "main" {
  # TODO
}

resource "aws_apigatewayv2_integration" "validator" {
  # TODO
}

resource "aws_apigatewayv2_route" "post_orders" {
  # TODO
}

resource "aws_apigatewayv2_stage" "default" {
  # TODO
}

resource "aws_lambda_permission" "apigw_validator" {
  # TODO
}


#--------------------------------------------------------------
# TODO 7: SQS Event Source Mapping（SQS → Processor Lambda）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping
#
#   event_source_arn = aws_sqs_queue.orders.arn
#   function_name    = aws_lambda_function.processor.arn
#   batch_size       = 10      # 每次最多傳 10 筆訊息給 Processor
#   enabled          = true
#
# ⚠️ 注意：這是讓 Lambda 自動消費 SQS 訊息的關鍵資源
#          Lambda 的 Event Source Mapping 需要 Processor IAM Role 有 sqs:ReceiveMessage 等權限
#          batch_size = 10 代表 SQS 累積到 10 筆，或等待 20 秒，才觸發一次 Lambda

resource "aws_lambda_event_source_mapping" "sqs_to_processor" {
  # TODO
}
