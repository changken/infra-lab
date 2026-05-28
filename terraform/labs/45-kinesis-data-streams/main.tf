#==============================================================
# Lab 45：Kinesis Data Streams 即時資料管道
#
# 資料流：
#   POST /events → API GW → Producer Lambda ──► Kinesis Data Stream
#                                                        │
#                                              Event Source Mapping
#                                                        │
#                                              Consumer Lambda
#                                                        │
#                                              DynamoDB（聚合計數）
#
# CloudWatch Alarm 監控消費者延遲：
#   GetRecords.IteratorAgeMilliseconds → SNS 告警
#==============================================================


#--------------------------------------------------------------
# TODO 1: Kinesis Data Stream
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesis_stream
#
# aws_kinesis_stream.events
#   name             = "${local.prefix}-events"
#   shard_count      = 1          ← 每個 shard 吞吐量：1 MB/s 寫入、2 MB/s 讀取
#   retention_period = 24         ← 資料保留 24 小時（預設值，可延長至 365 天）
#   tags             = local.common_tags
#
# 重要概念：
#   Partition Key → hash → 決定寫入哪個 shard（相同 key 的記錄保序）
#   Sequence Number → 每筆記錄在 shard 內的唯一排序標識
#
# ⚠️ shard_count 是 PROVISIONED 模式；ON_DEMAND 用 stream_mode_details 區塊（不需指定 shard 數）
# ⚠️ 增加 shard 提高吞吐量，但每個 shard 都有費用（$0.015/hr）

resource "aws_kinesis_stream" "events" {
  # TODO
}


#--------------------------------------------------------------
# TODO 2: DynamoDB 聚合計數表
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table
#
# aws_dynamodb_table.aggregation
#   name         = "${local.prefix}-event-counts"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "event_type"
#
#   attribute {
#     name = "event_type"
#     type = "S"
#   }
#
# Consumer Lambda 會對每個 event_type 執行 UpdateItem + ADD count :n
# 表結構：
#   event_type (PK)  | count   | last_updated
#   "page_view"      | 42      | "2024-01-01T..."
#   "purchase"       | 7       | "2024-01-01T..."

resource "aws_dynamodb_table" "aggregation" {
  # TODO
}


#--------------------------------------------------------------
# TODO 3: Producer 端（IAM + Lambda + API Gateway）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
#
# ① IAM Role for Producer Lambda
#   aws_iam_role.producer
#     name = "${local.prefix}-producer-role"
#     Trust: lambda.amazonaws.com
#
#   aws_iam_role_policy_attachment.producer_basic
#     policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
#
#   aws_iam_role_policy.producer_kinesis（inline policy）
#     讓 producer 可以寫入 Kinesis：
#     Action:   ["kinesis:PutRecord", "kinesis:PutRecords"]
#     Resource: aws_kinesis_stream.events.arn
#
# ② archive_file + Lambda
#   data "archive_file" "producer"
#     type        = "zip"
#     source_file = "${path.module}/src/producer.py"
#     output_path = "${path.module}/src/producer.zip"
#
#   aws_lambda_function.producer
#     function_name    = "${local.prefix}-producer"
#     handler          = "producer.handler"
#     runtime          = "python3.12"
#     role             = aws_iam_role.producer.arn
#     filename         = data.archive_file.producer.output_path
#     source_code_hash = data.archive_file.producer.output_base64sha256
#     environment { variables = { STREAM_NAME = aws_kinesis_stream.events.name } }
#
# ③ API Gateway HTTP API
#   aws_apigatewayv2_api.producer
#     name          = "${local.prefix}-producer-api"
#     protocol_type = "HTTP"
#
#   aws_apigatewayv2_integration.producer
#     integration_type = "AWS_PROXY"
#     integration_uri  = aws_lambda_function.producer.invoke_arn
#
#   aws_apigatewayv2_route.producer
#     route_key = "POST /events"
#
#   aws_apigatewayv2_stage.producer
#     name        = "$default"
#     auto_deploy = true
#
#   aws_lambda_permission.producer_apigw
#     principal  = "apigateway.amazonaws.com"
#     source_arn = "${aws_apigatewayv2_api.producer.execution_arn}/*/*"

resource "aws_iam_role" "producer" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "producer_basic" {
  # TODO
}

resource "aws_iam_role_policy" "producer_kinesis" {
  # TODO: kinesis:PutRecord + kinesis:PutRecords
}

data "archive_file" "producer" {
  # TODO
}

resource "aws_lambda_function" "producer" {
  # TODO: 記得加 environment { variables = { STREAM_NAME = ... } }
}

resource "aws_apigatewayv2_api" "producer" {
  # TODO
}

resource "aws_apigatewayv2_integration" "producer" {
  # TODO
}

resource "aws_apigatewayv2_route" "producer" {
  # TODO: route_key = "POST /events"
}

resource "aws_apigatewayv2_stage" "producer" {
  # TODO: name = "$default", auto_deploy = true
}

resource "aws_lambda_permission" "producer_apigw" {
  # TODO
}


#--------------------------------------------------------------
# TODO 4: Consumer 端（IAM + Lambda + Event Source Mapping）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping
#
# ① IAM Role for Consumer Lambda
#   aws_iam_role.consumer
#     name = "${local.prefix}-consumer-role"
#     Trust: lambda.amazonaws.com
#
#   aws_iam_role_policy_attachment.consumer_kinesis
#     policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole"
#     （包含 AWSLambdaBasicExecutionRole + Kinesis GetRecords/GetShardIterator/DescribeStream/ListShards）
#
#   aws_iam_role_policy.consumer_dynamodb（inline policy）
#     Action:   ["dynamodb:UpdateItem"]
#     Resource: aws_dynamodb_table.aggregation.arn
#
# ② archive_file + Lambda
#   aws_lambda_function.consumer
#     function_name    = "${local.prefix}-consumer"
#     handler          = "consumer.handler"
#     runtime          = "python3.12"
#     role             = aws_iam_role.consumer.arn
#     environment { variables = { TABLE_NAME = aws_dynamodb_table.aggregation.name } }
#
# ③ Event Source Mapping（Kinesis → Consumer Lambda）
#   aws_lambda_event_source_mapping.kinesis
#     event_source_arn = aws_kinesis_stream.events.arn
#     function_name    = aws_lambda_function.consumer.function_name
#     starting_position         = "LATEST"
#       ← "LATEST"：只消費新記錄（上線後生產環境用）
#       ← "TRIM_HORIZON"：從最舊未過期的記錄開始（重播用）
#     batch_size                = 100
#       ← 每次呼叫最多傳入 100 筆記錄（最大 10000）
#     bisect_batch_on_function_error = true
#       ← Lambda 失敗時，把 batch 切成兩半分別重試
#       ← 幫助隔離「毒藥訊息（poison pill）」
#
# ⚠️ Event Source Mapping 不需要 aws_lambda_permission（Lambda 服務自己負責輪詢）
# ⚠️ Kinesis 消費是「拉取（pull）」模式，Lambda Service 負責輪詢 shard iterator

resource "aws_iam_role" "consumer" {
  # TODO
}

resource "aws_iam_role_policy_attachment" "consumer_kinesis" {
  # TODO: AWSLambdaKinesisExecutionRole
}

resource "aws_iam_role_policy" "consumer_dynamodb" {
  # TODO: dynamodb:UpdateItem
}

data "archive_file" "consumer" {
  # TODO
}

resource "aws_lambda_function" "consumer" {
  # TODO: 記得加 environment { variables = { TABLE_NAME = ... } }
}

resource "aws_lambda_event_source_mapping" "kinesis" {
  # TODO: event_source_arn, function_name, starting_position, batch_size,
  #       bisect_batch_on_function_error
}


#--------------------------------------------------------------
# TODO 5: CloudWatch Alarm（消費者延遲監控）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm
#
# aws_sns_topic.alarms
#   name = "${local.prefix}-alarms"
#
# aws_sns_topic_subscription.email（count = var.notification_email != "" ? 1 : 0）
#   protocol  = "email"
#   endpoint  = var.notification_email
#
# aws_cloudwatch_metric_alarm.iterator_age
#   alarm_name          = "${local.prefix}-high-iterator-age"
#   namespace           = "AWS/Kinesis"
#   metric_name         = "GetRecords.IteratorAgeMilliseconds"
#   dimensions          = { StreamName = aws_kinesis_stream.events.name }
#   statistic           = "Maximum"
#   period              = 60
#   evaluation_periods  = 3
#   threshold           = 60000    ← 60 秒延遲告警（消費者跟不上生產者）
#   comparison_operator = "GreaterThanThreshold"
#   treat_missing_data  = "notBreaching"
#   alarm_actions       = [aws_sns_topic.alarms.arn]
#   ok_actions          = [aws_sns_topic.alarms.arn]
#
# 概念：IteratorAgeMilliseconds 是「最舊未處理記錄的時間戳」到「現在」的差值
#   = 0   → 消費者即時跟上
#   >> 0  → 消費者落後，可能需要增加 Lambda 並發或 Kinesis shard 數
#
# ⚠️ Kinesis 指標的 namespace 是 "AWS/Kinesis"，不是 "AWS/Lambda"

resource "aws_sns_topic" "alarms" {
  # TODO
}

resource "aws_sns_topic_subscription" "email" {
  # TODO: conditional with count
}

resource "aws_cloudwatch_metric_alarm" "iterator_age" {
  # TODO
}
