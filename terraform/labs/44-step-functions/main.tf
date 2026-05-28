#==============================================================
# Lab 44：Step Functions 工作流程編排
#
# 根配置建立以下資源：
#   - Lambda × 4（validate_order / reserve_inventory /
#                  process_payment / notify_customer）
#   - SNS Topic（訂單通知）
#   - Step Functions State Machine（Standard Workflow）
#   - CloudWatch Log Group（State Machine 執行日誌）
#   - IAM Role × 2（Lambda 執行角色 / Step Functions 執行角色）
#
# 狀態機資料流：
#   input ──► ValidateOrder ──► ReserveInventory ──► ProcessPayment ──► NotifyCustomer ──► OrderComplete
#                │                    │                    │
#             Catch                 Catch             Retry + Catch
#                └────────────────────┴────────────────────┘
#                                    │
#                               OrderFailed（Fail State）
#==============================================================


#--------------------------------------------------------------
# TODO 1: Lambda IAM Role
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# 建立所有 Lambda 函數共用的 IAM Role：
#
# aws_iam_role.lambda
#   name = "${local.prefix}-lambda-role"
#   assume_role_policy → Trust: lambda.amazonaws.com
#
# aws_iam_role_policy_attachment.lambda_basic
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
#
# aws_iam_role_policy.lambda_sns（inline policy）
#   讓 notify_customer Lambda 可以發佈到 SNS：
#   {
#     "Effect": "Allow",
#     "Action": "sns:Publish",
#     "Resource": aws_sns_topic.orders.arn
#   }
#
# ⚠️ 雖然只有 notify_customer 需要 SNS，但共用 Role 簡化管理
# ⚠️ inline policy 可以引用 aws_sns_topic.orders，Terraform 會自動解析依賴

resource "aws_iam_role" "lambda" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  # TODO
}

resource "aws_iam_role_policy" "lambda_sns" {
  # TODO
}


#--------------------------------------------------------------
# TODO 2: Lambda 函數（4 個）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
#
# 先用 archive_file 打包原始碼，再建立 Lambda function
#
# ① validate_order
#   data "archive_file" "validate_order"
#     type        = "zip"
#     source_file = "${path.module}/src/validate_order.py"
#     output_path = "${path.module}/src/validate_order.zip"
#
#   resource "aws_lambda_function" "validate_order"
#     function_name = "${local.prefix}-validate-order"
#     filename      = data.archive_file.validate_order.output_path
#     source_code_hash = data.archive_file.validate_order.output_base64sha256
#     handler       = "validate_order.handler"
#     runtime       = "python3.12"
#     role          = aws_iam_role.lambda.arn
#
# ② reserve_inventory（同上，無額外 env var）
#
# ③ process_payment（同上，無額外 env var）
#
# ④ notify_customer（需要額外的 environment variables）
#   environment {
#     variables = {
#       SNS_TOPIC_ARN = aws_sns_topic.orders.arn
#     }
#   }
#
# ⚠️ source_code_hash 確保程式碼更新時 Lambda 會重新部署

data "archive_file" "validate_order" {
  # TODO
}

data "archive_file" "reserve_inventory" {
  # TODO
}

data "archive_file" "process_payment" {
  # TODO
}

data "archive_file" "notify_customer" {
  # TODO
}

resource "aws_lambda_function" "validate_order" {
  # TODO
}

resource "aws_lambda_function" "reserve_inventory" {
  # TODO
}

resource "aws_lambda_function" "process_payment" {
  # TODO
}

resource "aws_lambda_function" "notify_customer" {
  # TODO: 記得加 environment { variables = { SNS_TOPIC_ARN = ... } }
}


#--------------------------------------------------------------
# TODO 3: SNS Topic（訂單通知）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic
#
# aws_sns_topic.orders
#   name = "${local.prefix}-orders"
#   tags = local.common_tags
#
# aws_sns_topic_subscription.email（條件建立）
#   count     = var.notification_email != "" ? 1 : 0
#   topic_arn = aws_sns_topic.orders.arn
#   protocol  = "email"
#   endpoint  = var.notification_email
#
# ⚠️ SNS email 訂閱需要收信確認（訂閱後到信箱點 "Confirm subscription"）

resource "aws_sns_topic" "orders" {
  # TODO
}

resource "aws_sns_topic_subscription" "email" {
  # TODO: conditional with count
}


#--------------------------------------------------------------
# TODO 4: Step Functions IAM Role
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# aws_iam_role.sfn
#   name = "${local.prefix}-sfn-role"
#   Trust policy: states.amazonaws.com
#
# aws_iam_role_policy.sfn（inline policy）
#   需要包含兩個權限區塊：
#
#   ① 呼叫 Lambda（Resource 用 list 列出 4 個 Lambda ARN）：
#     "Action": "lambda:InvokeFunction"
#     "Resource": [
#       aws_lambda_function.validate_order.arn,
#       aws_lambda_function.reserve_inventory.arn,
#       aws_lambda_function.process_payment.arn,
#       aws_lambda_function.notify_customer.arn,
#     ]
#
#   ② 寫入 CloudWatch Logs（Resource = "*"，Logs 不支援 resource-level）：
#     "Action": [
#       "logs:CreateLogDelivery", "logs:GetLogDelivery",
#       "logs:UpdateLogDelivery", "logs:DeleteLogDelivery",
#       "logs:ListLogDeliveries", "logs:PutLogEvents",
#       "logs:PutResourcePolicy", "logs:DescribeLogGroups",
#       "logs:DescribeResourcePolicies"
#     ]
#
# ⚠️ 沒有 logs 權限，logging_configuration 會 apply 失敗

resource "aws_iam_role" "sfn" {
  # TODO
}

resource "aws_iam_role_policy" "sfn" {
  # TODO
}


#--------------------------------------------------------------
# TODO 5: CloudWatch Log Group + State Machine
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine
#
# ① aws_cloudwatch_log_group.sfn
#   name              = "/aws/states/${local.prefix}-order-workflow"
#   retention_in_days = 7
#
# ② aws_sfn_state_machine.order_workflow
#   name     = "${local.prefix}-order-workflow"
#   role_arn = aws_iam_role.sfn.arn
#   type     = "STANDARD"
#
#   definition = jsonencode({...})   ← ASL（Amazon States Language）JSON
#
#   使用 jsonencode() 的原因：可以直接在 HCL 物件中插入 Lambda ARN
#
#   ASL 結構：
#   {
#     Comment = "Order processing workflow"
#     StartAt = "ValidateOrder"
#     States = {
#       ValidateOrder = {
#         Type     = "Task"
#         Resource = aws_lambda_function.validate_order.arn  ← 直接引用
#         Retry = [{
#           ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
#           IntervalSeconds = 2
#           MaxAttempts     = 2
#           BackoffRate     = 1.5
#         }]
#         Catch = [{
#           ErrorEquals = ["InvalidOrderError"]
#           Next        = "OrderFailed"
#           ResultPath  = "$.error"   ← 把錯誤訊息存到 $.error，不覆蓋原始 input
#         }]
#         Next = "ReserveInventory"
#       }
#
#       ReserveInventory = {
#         Type     = "Task"
#         Resource = aws_lambda_function.reserve_inventory.arn
#         Catch = [{
#           ErrorEquals = ["InsufficientInventoryError"]
#           Next        = "OrderFailed"
#           ResultPath  = "$.error"
#         }]
#         Next = "ProcessPayment"
#       }
#
#       ProcessPayment = {
#         Type     = "Task"
#         Resource = aws_lambda_function.process_payment.arn
#         Retry = [{
#           ErrorEquals     = ["PaymentRetryableError"]
#           IntervalSeconds = 5
#           MaxAttempts     = 3
#           BackoffRate     = 2.0
#         }]
#         Catch = [{
#           ErrorEquals = ["PaymentFailedError"]
#           Next        = "OrderFailed"
#           ResultPath  = "$.error"
#         }]
#         Next = "NotifyCustomer"
#       }
#
#       NotifyCustomer = {
#         Type     = "Task"
#         Resource = aws_lambda_function.notify_customer.arn
#         Next     = "OrderComplete"
#       }
#
#       OrderComplete = { Type = "Succeed" }
#
#       OrderFailed = {
#         Type  = "Fail"
#         Error = "OrderProcessingFailed"
#       }
#     }
#   })
#
#   logging_configuration {
#     level                  = "ERROR"
#     include_execution_data = false
#     log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
#   }
#
# ⚠️ ResultPath = "$.error" 讓 Catch 把例外資訊附加到原始 input，而不是替換它
# ⚠️ Standard Workflow：exactly-once + 無限時長；Express：at-least-once + 最長 5 分鐘

resource "aws_cloudwatch_log_group" "sfn" {
  # TODO
}

resource "aws_sfn_state_machine" "order_workflow" {
  # TODO
}
