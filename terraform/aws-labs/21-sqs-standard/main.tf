#==============================================================
# 學習目標：SQS Standard Queue + Dead Letter Queue + Lambda Consumer
#
# 架構：
#   你發送訊息到 SQS Main Queue
#     → Lambda 自動被觸發（Event Source Mapping）
#         → 處理訊息（印 log）
#         → 若 Lambda 失敗超過 max_receive_count 次
#             → 訊息自動移入 Dead Letter Queue（DLQ）
#
# 新概念：
#   aws_sqs_queue         → 建立 SQS 佇列
#   redrive_policy        → 設定 DLQ 的條件（幾次失敗後轉入）
#   visibility_timeout    → 訊息被拿走後暫時隱藏的時間
#   long_polling          → receive_wait_time_seconds = 20，減少空輪詢費用
#   aws_lambda_event_source_mapping → 讓 Lambda 自動消費 SQS 訊息
#
# 完成順序：1 → 2 → 3 → 4 → 5
#==============================================================


# 已完成：Lambda zip 打包
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/consumer.py"
  output_path = "${path.module}/src/consumer.zip"
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
# TODO 1: Dead Letter Queue（DLQ）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
#
# DLQ 本身就是一個普通的 SQS Queue，不需要特別設定。
# 它的存在意義：主 Queue 的訊息失敗 N 次後自動轉過來，方便排查。
#
# 需要設定：
#   name                      = "${var.project}-dlq"
#   message_retention_seconds = 1209600   # 14 天（DLQ 通常保留久一點，方便除錯）
#   tags                      = merge(local.common_tags, { Name = "${var.project}-dlq" })

resource "aws_sqs_queue" "dlq" {
  # TODO
  name                      = "${var.project}-dlq"
  message_retention_seconds = 1209600 # 14 天（DLQ 通常保留久一點，方便除錯）
  tags                      = merge(local.common_tags, { Name = "${var.project}-dlq" })
}


#--------------------------------------------------------------
# TODO 2: Main SQS Queue（含 DLQ redrive policy）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
#
# 這是主要的工作佇列，有幾個關鍵參數要理解：
#
#   visibility_timeout_seconds = var.visibility_timeout_seconds
#     → 消費者拿走訊息後，其他人看不到它的時間。
#     → ⚠️ 必須 >= Lambda timeout（Lambda 預設 3 秒，這裡設 30）
#     → 若 Lambda 還沒處理完就逾時，訊息會重新出現被其他消費者拿走（重複處理）
#
#   receive_wait_time_seconds = 20
#     → Long Polling：等待最多 20 秒再回應空結果
#     → 比 Short Polling（立刻回應）節省 API 呼叫費用
#
#   message_retention_seconds = 345600   # 4 天
#
#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.dlq.arn
#     maxReceiveCount     = var.max_receive_count   # 失敗幾次後送 DLQ
#   })
#
#   tags = merge(local.common_tags, { Name = "${var.project}-queue" })

resource "aws_sqs_queue" "main" {
  # TODO
  name                       = "${var.project}-queue"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  receive_wait_time_seconds  = 20
  message_retention_seconds  = 345600 # 4 天
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count # 失敗幾次後
  })
  tags = merge(local.common_tags, { Name = "${var.project}-queue" })
}


#--------------------------------------------------------------
# TODO 3: Lambda IAM Policy（SQS 消費權限）
#--------------------------------------------------------------
# Lambda 要從 SQS 拉訊息並刪除訊息，需要以下權限：
#   - sqs:ReceiveMessage
#   - sqs:DeleteMessage
#   - sqs:GetQueueAttributes
#
# ⚠️ 這三個是 Event Source Mapping 必要的最小權限，少一個就會讓 mapping 失效。
#
# 需要設定：
#   name = "sqs-consume"
#   role = aws_iam_role.lambda.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Action = [
#         "sqs:ReceiveMessage",
#         "sqs:DeleteMessage",
#         "sqs:GetQueueAttributes"
#       ]
#       Resource = aws_sqs_queue.main.arn
#       # ⚠️ 只給 main queue 的 ARN，不要給 "*"
#     }]
#   })

resource "aws_iam_role_policy" "lambda_sqs" {
  # TODO
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
      Resource = aws_sqs_queue.main.arn
    }]
  })
}


#--------------------------------------------------------------
# TODO 4: Lambda Function（SQS 消費者）
#--------------------------------------------------------------
# 跟前幾個 Lab 結構相同，注意 timeout 要 <= visibility_timeout_seconds：
#
#   function_name    = "${var.project}-consumer"
#   role             = aws_iam_role.lambda.arn
#   filename         = data.archive_file.lambda_zip.output_path
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256
#   runtime          = "python3.12"
#   handler          = "consumer.handler"
#   timeout          = 25   # < visibility_timeout_seconds (30)
#   tags             = merge(local.common_tags, { Name = "${var.project}-consumer" })

resource "aws_lambda_function" "consumer" {
  # TODO
  function_name    = "${var.project}-consumer"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  handler          = "consumer.handler"
  timeout          = 25 # < visibility_timeout_seconds (30)
  tags             = merge(local.common_tags, { Name = "${var.project}-consumer" })
}


#--------------------------------------------------------------
# TODO 5: Event Source Mapping（SQS → Lambda 自動觸發）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping
#
# 這是 SQS 和 Lambda 整合的關鍵：Lambda 輪詢 SQS，有訊息時自動觸發。
# 不需要像 S3 那樣設定 permission，因為 polling 是 Lambda 主動發起的。
#
#   event_source_arn                   = aws_sqs_queue.main.arn
#   function_name                      = aws_lambda_function.consumer.arn
#   batch_size                         = 10     # 一次最多拉幾筆訊息
#   maximum_batching_window_in_seconds = 5      # 等幾秒再湊成一批（節省 Lambda 呼叫次數）
#   enabled                            = true
#
# ⚠️ 思考：batch_size = 10 時，若 Lambda 處理到第 5 筆失敗了，整批 10 筆都會重試。
#    這就是為什麼消費者邏輯要設計成冪等（idempotent）。

resource "aws_lambda_event_source_mapping" "sqs" {
  # TODO
  event_source_arn                   = aws_sqs_queue.main.arn
  function_name                      = aws_lambda_function.consumer.arn
  batch_size                         = 10 # 一次最多拉幾筆訊息
  maximum_batching_window_in_seconds = 5  # 等幾秒再湊成一批（節省 Lambda 呼叫次數）
  enabled                            = true
}
