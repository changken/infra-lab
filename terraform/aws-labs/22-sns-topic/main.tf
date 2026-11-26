#==============================================================
# 學習目標：SNS Topic + 三種訂閱類型（Email / SQS / Lambda）+ Filter Policy
#
# 架構：
#   你發布訊息到 SNS Topic
#     ├── Email 訂閱者（所有訊息）
#     ├── SQS 訂閱者（只接收 priority=high 的訊息）← Filter Policy
#     └── Lambda 訂閱者（所有訊息，直接被 SNS 推送觸發）
#
# 新概念（跟 Lab 21 SQS 的關鍵差異）：
#   SNS 是「推送（Push）」模型 vs SQS 是「拉取（Pull）」模型
#   aws_sns_topic                → 建立 Topic
#   aws_sns_topic_subscription   → 綁定訂閱者（protocol 決定類型）
#   aws_sqs_queue_policy         → SNS 推送到 SQS 時，SQS 需要明確授權
#   aws_lambda_permission        → SNS 推送到 Lambda 時，Lambda 需要明確授權
#   filter_policy                → 讓 SQS/Lambda 只接收符合條件的訊息
#
# ⚠️ 兩個常見陷阱：
#   1. SNS → SQS：必須設定 SQS Queue Policy，SNS 才有權寫入
#   2. SNS → Lambda：必須設定 Lambda Permission，SNS 才有權呼叫
#      （跟 Lab 21 的 Event Source Mapping 不同，那個是 Lambda 主動拉取）
#
# 完成順序：1 → 2 → 3 → 4 → 5
#==============================================================


# 已完成：Lambda zip 打包
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/src/handler.zip"
}

# 已完成：Lambda IAM Role
resource "aws_iam_role" "lambda" {
  name = "${var.project}-lambda-role"
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
# TODO 1: SNS Topic
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic
#
# SNS Topic 本身很簡單，只需要名稱和 tags。
# 訂閱者（Subscriptions）是獨立的資源，後面再設定。
#
# 需要設定：
#   name = "${var.project}-topic"
#   tags = merge(local.common_tags, { Name = "${var.project}-topic" })

resource "aws_sns_topic" "main" {
  # TODO
}


#--------------------------------------------------------------
# TODO 2: Email 訂閱
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription
#
# ⚠️ apply 後 AWS 會寄一封確認信到 notification_email。
#    必須點信中的連結，訂閱才會變成 Confirmed 狀態。
#    Terraform plan/apply 不會等待確認，狀態會顯示 PendingConfirmation。
#
# 需要設定：
#   topic_arn = aws_sns_topic.main.arn
#   protocol  = "email"
#   endpoint  = var.notification_email

resource "aws_sns_topic_subscription" "email" {
  # TODO
  topic_arn = aws_sns_topic.main.arn
  protocol  = "email"
  endpoint  = var.notification_email
}


#--------------------------------------------------------------
# TODO 3: SQS Queue + Queue Policy（授權 SNS 寫入）
#--------------------------------------------------------------
# 文件（queue）:  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
# 文件（policy）: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy
#
# ── SQS Queue ──
#   name                      = "${var.project}-subscriber-queue"
#   message_retention_seconds = 86400   # 1 天（測試用，不需要留太久）
#   tags                      = merge(local.common_tags, { Name = "${var.project}-subscriber-queue" })
#
# ── SQS Queue Policy ──
# ⚠️ 這是 SNS → SQS 最常忘記的步驟！
#    SNS 向 SQS 推送訊息時，SQS 必須有 Policy 允許 SNS 這個服務寫入。
#    少了這個，apply 會成功，但 SNS 發布後 SQS 不會收到任何訊息。
#
#   queue_url = aws_sqs_queue.subscriber.id
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "sns.amazonaws.com" }
#       Action    = "sqs:SendMessage"
#       Resource  = aws_sqs_queue.subscriber.arn
#       Condition = {
#         ArnEquals = { "aws:SourceArn" = aws_sns_topic.main.arn }
#         # ⚠️ 限定只有這個 SNS Topic 可以寫入，不要開放給所有 SNS
#       }
#     }]
#   })

resource "aws_sqs_queue" "subscriber" {
  # TODO
  name                      = "${var.project}-subscriber-queue"
  message_retention_seconds = 86400 # 1 天（測試用，不需要留太久）
  tags                      = merge(local.common_tags, { Name = "${var.project}-subscriber-queue" })

}

resource "aws_sqs_queue_policy" "subscriber" {
  # TODO
  queue_url = aws_sqs_queue.subscriber.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.subscriber.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.main.arn }
        # ⚠️ 限定只有這個 SNS Topic 可以寫入，不要開放給所有 SNS
      }
    }]
  })
}


#--------------------------------------------------------------
# TODO 4: SNS → SQS 訂閱（含 Filter Policy）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription
#
# Filter Policy 讓 SQS 只接收帶有 "priority": "high" 屬性的訊息。
# 不符合的訊息直接被 SNS 丟棄，SQS 不會收到。
#
# 需要設定：
#   topic_arn = aws_sns_topic.main.arn
#   protocol  = "sqs"
#   endpoint  = aws_sqs_queue.subscriber.arn
#
#   filter_policy = jsonencode({
#     priority = ["high"]
#     # 訊息的 MessageAttributes 中 priority 必須等於 "high" 才會被投遞
#   })
#
#   filter_policy_scope = "MessageAttributes"   # 預設值，也可以是 "MessageBody"

resource "aws_sns_topic_subscription" "sqs" {
  # TODO
  topic_arn           = aws_sns_topic.main.arn
  protocol            = "sqs"
  endpoint            = aws_sqs_queue.subscriber.arn
  filter_policy       = jsonencode({ priority = ["high"] })
  filter_policy_scope = "MessageAttributes"
}


#--------------------------------------------------------------
# TODO 5: Lambda Function + Lambda Permission + SNS → Lambda 訂閱
#--------------------------------------------------------------
# 文件（permission）:    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission
# 文件（subscription）: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription
#
# ── Lambda Function ──
#   function_name    = "${var.project}-handler"
#   role             = aws_iam_role.lambda.arn
#   filename         = data.archive_file.lambda_zip.output_path
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256
#   runtime          = "python3.12"
#   handler          = "handler.handler"
#   tags             = merge(local.common_tags, { Name = "${var.project}-handler" })
#
# ── Lambda Permission ──
# ⚠️ SNS 「推送」呼叫 Lambda，和 S3 觸發 Lambda 一樣需要 Permission。
#    跟 Lab 21 的 Event Source Mapping（Lambda 主動拉取）不同！
#
#   statement_id  = "AllowSNSInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.handler.function_name
#   principal     = "sns.amazonaws.com"
#   source_arn    = aws_sns_topic.main.arn
#
# ── SNS → Lambda 訂閱（無 Filter，接收所有訊息）──
#   topic_arn = aws_sns_topic.main.arn
#   protocol  = "lambda"
#   endpoint  = aws_lambda_function.handler.arn

resource "aws_lambda_function" "handler" {
  # TODO
  function_name    = "${var.project}-handler"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.handler"
  tags             = merge(local.common_tags, { Name = "${var.project}-handler" })
}

resource "aws_lambda_permission" "sns" {
  # TODO
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.handler.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.main.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  # TODO
  topic_arn = aws_sns_topic.main.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.handler.arn
}
