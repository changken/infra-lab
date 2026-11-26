#==============================================================
# 學習目標：SNS → 多個 SQS Fan-out Pattern（可靠廣播）
#
# 場景：電商訂單成立後，需要同時通知庫存服務和通知服務
#
# 架構：
#   你發布 order.created 事件到 SNS Topic
#     ├── SQS: Inventory Queue → Lambda（扣庫存）
#     └── SQS: Notification Queue → Lambda（寄通知）
#
# 為什麼不直接用 SNS → 2 個 Lambda？
#   SNS 直接觸發 Lambda 時，若 Lambda 失敗，訊息就遺失。
#   加上 SQS 作為緩衝層：
#     → Lambda 失敗 → 訊息留在 SQS → 自動重試 → 超過次數進 DLQ
#     → 每個下游服務獨立處理，互不影響
#
# 新概念（整合 Lab 21 + Lab 22）：
#   Fan-out = SNS（廣播）+ SQS（緩衝 + 重試）
#   每個 SQS 各有獨立的 DLQ → 某個服務掛了不影響其他服務
#   Queue Policy（SNS → SQS 必備）
#   Event Source Mapping（Lambda 拉取 SQS，非 SNS 推送）
#
# 完成順序：1 → 2 → 3 → 4 → 5
#==============================================================


# 已完成：Lambda zip 打包
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/src/workers.zip"
  excludes    = ["workers.zip"]
}

# 已完成：Lambda IAM Role（兩個 worker 共用）
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

# 已完成：Lambda SQS 消費權限（兩個 Queue 的 ARN 都要包含）
resource "aws_iam_role_policy" "lambda_sqs" {
  name = "sqs-consume"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = [
        aws_sqs_queue.inventory.arn,
        aws_sqs_queue.notification.arn,
      ]
    }]
  })
}


#--------------------------------------------------------------
# TODO 1: SNS Topic + 2 個 DLQ
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
#
# ── SNS Topic ──
#   name = "${var.project}-orders"
#   tags = merge(local.common_tags, { Name = "${var.project}-orders" })
#
# ── DLQ for Inventory（庫存服務失敗的訊息落地處）──
#   name                      = "${var.project}-inventory-dlq"
#   message_retention_seconds = 1209600   # 14 天
#   tags                      = merge(local.common_tags, { Name = "${var.project}-inventory-dlq" })
#
# ── DLQ for Notification（通知服務失敗的訊息落地處）──
#   name                      = "${var.project}-notification-dlq"
#   message_retention_seconds = 1209600
#   tags                      = merge(local.common_tags, { Name = "${var.project}-notification-dlq" })
#
# ⚠️ 思考：為什麼每個 SQS 有獨立的 DLQ，而不是共用一個？
#   → 庫存失敗和通知失敗是不同的問題，混在一起的 DLQ 很難 debug

resource "aws_sns_topic" "orders" {
  # TODO
  name = "${var.project}-orders"
  tags = merge(local.common_tags, { Name = "${var.project}-orders" })
}

resource "aws_sqs_queue" "inventory_dlq" {
  # TODO
  name                      = "${var.project}-inventory-dlq"
  message_retention_seconds = 1209600
  tags                      = merge(local.common_tags, { Name = "${var.project}-inventory-dlq" })
}

resource "aws_sqs_queue" "notification_dlq" {
  # TODO
  name                      = "${var.project}-notification-dlq"
  message_retention_seconds = 1209600
  tags                      = merge(local.common_tags, { Name = "${var.project}-notification-dlq" })
}


#--------------------------------------------------------------
# TODO 2: Inventory SQS Queue + Queue Policy
#--------------------------------------------------------------
# 文件（queue）:  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
# 文件（policy）: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy
#
# ── SQS Queue ──
#   name                       = "${var.project}-inventory"
#   visibility_timeout_seconds = 30
#   receive_wait_time_seconds  = 20
#   message_retention_seconds  = 345600   # 4 天
#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.inventory_dlq.arn
#     maxReceiveCount     = var.max_receive_count
#   })
#   tags = merge(local.common_tags, { Name = "${var.project}-inventory" })
#
# ── Queue Policy（授權 SNS 寫入此 Queue）──
#   queue_url = aws_sqs_queue.inventory.id
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "sns.amazonaws.com" }
#       Action    = "sqs:SendMessage"
#       Resource  = aws_sqs_queue.inventory.arn
#       Condition = {
#         ArnEquals = { "aws:SourceArn" = aws_sns_topic.orders.arn }
#       }
#     }]
#   })

resource "aws_sqs_queue" "inventory" {
  # TODO
  name                       = "${var.project}-inventory"
  visibility_timeout_seconds = 30
  receive_wait_time_seconds  = 20
  message_retention_seconds  = 345600
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.inventory_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
  tags = merge(local.common_tags, { Name = "${var.project}-inventory" })
}

resource "aws_sqs_queue_policy" "inventory" {
  # TODO
  queue_url = aws_sqs_queue.inventory.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.inventory.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.orders.arn }
      }
    }]
  })
}


#--------------------------------------------------------------
# TODO 3: Notification SQS Queue + Queue Policy
#--------------------------------------------------------------
# 結構和 TODO 2 完全相同，只是名稱和 DLQ 換成 notification 版本。
#
# ── SQS Queue ──
#   name                       = "${var.project}-notification"
#   visibility_timeout_seconds = 30
#   receive_wait_time_seconds  = 20
#   message_retention_seconds  = 345600
#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.notification_dlq.arn
#     maxReceiveCount     = var.max_receive_count
#   })
#   tags = merge(local.common_tags, { Name = "${var.project}-notification" })
#
# ── Queue Policy ──
#   (和 inventory 相同結構，Resource 換成 notification queue 的 ARN)

resource "aws_sqs_queue" "notification" {
  # TODO
  name                       = "${var.project}-notification"
  visibility_timeout_seconds = 30
  receive_wait_time_seconds  = 20
  message_retention_seconds  = 345600
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notification_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
  tags = merge(local.common_tags, { Name = "${var.project}-notification" })
}

resource "aws_sqs_queue_policy" "notification" {
  # TODO
  queue_url = aws_sqs_queue.notification.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.notification.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.orders.arn }
      }
    }]
  })
}


#--------------------------------------------------------------
# TODO 4: SNS → SQS 訂閱（Fan-out：一個 Topic，兩個 Queue）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription
#
# 兩個訂閱都訂同一個 Topic，但各自指向不同的 SQS Queue。
# 這就是 Fan-out：一次 publish，兩個 Queue 都收到一份完整的訊息。
#
# ── Inventory 訂閱 ──
#   topic_arn = aws_sns_topic.orders.arn
#   protocol  = "sqs"
#   endpoint  = aws_sqs_queue.inventory.arn
#
# ── Notification 訂閱 ──
#   topic_arn = aws_sns_topic.orders.arn
#   protocol  = "sqs"
#   endpoint  = aws_sqs_queue.notification.arn
#
# ⚠️ 注意：這裡不設 filter_policy，兩個 Queue 都接收所有訂單事件。
#   如果只有特定訂單類型需要扣庫存，才需要加 filter_policy。

resource "aws_sns_topic_subscription" "inventory" {
  # TODO
  topic_arn = aws_sns_topic.orders.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.inventory.arn
}

resource "aws_sns_topic_subscription" "notification" {
  # TODO
  topic_arn = aws_sns_topic.orders.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notification.arn
}


#--------------------------------------------------------------
# TODO 5: Lambda Functions + Event Source Mappings
#--------------------------------------------------------------
# 文件（ESM）: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping
#
# ── Lambda: Inventory Worker ──
#   function_name    = "${var.project}-inventory-worker"
#   role             = aws_iam_role.lambda.arn
#   filename         = data.archive_file.lambda_zip.output_path
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256
#   runtime          = "python3.12"
#   handler          = "inventory_worker.handler"
#   timeout          = 25
#   tags             = merge(local.common_tags, { Name = "${var.project}-inventory-worker" })
#
# ── Lambda: Notification Worker ──
#   function_name    = "${var.project}-notification-worker"
#   handler          = "notification_worker.handler"
#   (其餘和 inventory 相同)
#
# ── Event Source Mapping: inventory queue → inventory worker ──
#   event_source_arn = aws_sqs_queue.inventory.arn
#   function_name    = aws_lambda_function.inventory_worker.arn
#   batch_size       = 10
#   enabled          = true
#
# ── Event Source Mapping: notification queue → notification worker ──
#   event_source_arn = aws_sqs_queue.notification.arn
#   function_name    = aws_lambda_function.notification_worker.arn
#   batch_size       = 10
#   enabled          = true
#
# ⚠️ 為什麼用 ESM（Pull）而不是 SNS 直接 Push 到 Lambda？
#   → SQS 提供緩衝：某個 worker Lambda 掛了，訊息仍在 Queue 裡等待重試
#   → SNS 直接 Push 到 Lambda：Lambda 失敗 → 訊息消失（SNS 最多重試 3 次後放棄）
#   → Fan-out + SQS = 可靠廣播（Reliable Fan-out）

resource "aws_lambda_function" "inventory_worker" {
  # TODO
  function_name    = "${var.project}-inventory-worker"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  handler          = "inventory_worker.handler"
  timeout          = 25
  tags             = merge(local.common_tags, { Name = "${var.project}-inventory-worker" })
}

resource "aws_lambda_function" "notification_worker" {
  # TODO
  function_name    = "${var.project}-notification-worker"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  handler          = "notification_worker.handler"
  timeout          = 25
  tags             = merge(local.common_tags, { Name = "${var.project}-notification-worker" })
}

resource "aws_lambda_event_source_mapping" "inventory" {
  # TODO
  event_source_arn = aws_sqs_queue.inventory.arn
  function_name    = aws_lambda_function.inventory_worker.arn
  batch_size       = 10
  enabled          = true
}

resource "aws_lambda_event_source_mapping" "notification" {
  # TODO
  event_source_arn = aws_sqs_queue.notification.arn
  function_name    = aws_lambda_function.notification_worker.arn
  batch_size       = 10
  enabled          = true
}




#==============================================================
# [進階參考] 生產環境告警架構：DLQ → CloudWatch Alarm → SNS 告警
#
# 當 DLQ 有訊息進入時，透過 CloudWatch Alarm 觸發 SNS 告警通知，
# 避免每一筆 dead letter 都直接爆炸式通知的問題。
#
# 架構：
#   DLQ（有訊息）
#     └── CloudWatch Alarm（ApproximateNumberOfMessagesVisible > 0）
#           └── SNS Alert Topic
#                 ├── Email 訂閱（通知工程師）
#                 └── Slack / PagerDuty（進階整合）
#
# ⚠️ 注意：此處的 SNS alerts topic 是給 OPS 告警用的，
#          與業務用的 SNS orders topic 職責完全不同，請勿混淆。
#==============================================================

# # ── 告警專用 SNS Topic ──
# resource "aws_sns_topic" "alerts" {
#   name = "${var.project}-alerts"
#   tags = merge(local.common_tags, { Name = "${var.project}-alerts" })
# }

# # ── Email 訂閱（訂閱確認信會寄到此 email，需手動點擊確認）──
# resource "aws_sns_topic_subscription" "alert_email" {
#   topic_arn = aws_sns_topic.alerts.arn
#   protocol  = "email"
#   endpoint  = "oncall@example.com"   # TODO: 替換為實際 email
# }

# # ── Inventory DLQ 告警 ──
# resource "aws_cloudwatch_metric_alarm" "inventory_dlq" {
#   alarm_name          = "${var.project}-inventory-dlq-not-empty"
#   alarm_description   = "Inventory DLQ 有訊息，需要人工介入檢查失敗原因"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 1
#   metric_name         = "ApproximateNumberOfMessagesVisible"
#   namespace           = "AWS/SQS"
#   period              = 60       # 每 60 秒評估一次
#   statistic           = "Sum"
#   threshold           = 0        # > 0 就告警
#   treat_missing_data  = "notBreaching"  # 沒有流量時不誤報
#
#   dimensions = {
#     QueueName = aws_sqs_queue.inventory_dlq.name
#   }
#
#   alarm_actions = [aws_sns_topic.alerts.arn]  # 進入 ALARM 狀態時通知
#   ok_actions    = [aws_sns_topic.alerts.arn]  # 恢復 OK 狀態時也通知（確認問題已解）
#
#   tags = merge(local.common_tags, { Name = "${var.project}-inventory-dlq-alarm" })
# }

# # ── Notification DLQ 告警（結構與 Inventory 相同）──
# resource "aws_cloudwatch_metric_alarm" "notification_dlq" {
#   alarm_name          = "${var.project}-notification-dlq-not-empty"
#   alarm_description   = "Notification DLQ 有訊息，需要人工介入檢查失敗原因"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 1
#   metric_name         = "ApproximateNumberOfMessagesVisible"
#   namespace           = "AWS/SQS"
#   period              = 60
#   statistic           = "Sum"
#   threshold           = 0
#   treat_missing_data  = "notBreaching"
#
#   dimensions = {
#     QueueName = aws_sqs_queue.notification_dlq.name
#   }
#
#   alarm_actions = [aws_sns_topic.alerts.arn]
#   ok_actions    = [aws_sns_topic.alerts.arn]
#
#   tags = merge(local.common_tags, { Name = "${var.project}-notification-dlq-alarm" })
# }