#==============================================================
# 學習目標：EventBridge Rules（Schedule + Event Pattern）+ Custom Event Bus
#
# 架構：
#   排程觸發（rate/cron）
#     └── Schedule Rule → Lambda（定時工作）
#
#   自訂事件流
#     你 → put-events → Custom Event Bus
#       └── Pattern Rule（過濾 source + detail-type + detail）
#             └── Lambda（事件處理器）
#
# 新概念：
#   aws_cloudwatch_event_bus    → 建立 Custom Event Bus（Terraform 資源名稱仍是 cloudwatch_event）
#   aws_cloudwatch_event_rule   → 建立 Rule（Schedule 或 Event Pattern）
#   aws_cloudwatch_event_target → 把 Rule 連接到 Target（Lambda / SQS / SNS 等）
#   event_pattern               → JSON 過濾條件，決定哪些事件觸發這條 Rule
#
# ⚠️ Terraform 資源名稱的歷史包袱：
#   EventBridge 原本叫 CloudWatch Events，所以 Terraform 資源名稱
#   仍然是 aws_cloudwatch_event_xxx，不是 aws_eventbridge_xxx。
#   功能是同一個服務，不要被名稱混淆。
#
# ⚠️ 和 SNS/SQS 的差異：
#   SNS：你主動 publish 到 Topic，SNS 推給訂閱者
#   SQS：你主動 send 到 Queue，消費者拉取
#   EventBridge：事件自動路由（AWS 服務事件 or 自訂事件）→ Rule 過濾 → Target
#
# 完成順序：1 → 2 → 3 → 4 → 5
#==============================================================


# 已完成：Lambda zip 打包（兩個函數共用同一份 zip）
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/src/handlers.zip"
  excludes    = ["handlers.zip"]
}

# 已完成：Lambda IAM Role（兩個函數共用）
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
# TODO 1: Lambda（排程觸發目標）+ Lambda Permission
#--------------------------------------------------------------
# EventBridge 「推送」呼叫 Lambda，和 SNS 一樣需要 Lambda Permission。
# principal 是 "events.amazonaws.com"（不是 sns.amazonaws.com）。
#
# ── Lambda Function ──
#   function_name    = "${var.project}-scheduler"
#   role             = aws_iam_role.lambda.arn
#   filename         = data.archive_file.lambda_zip.output_path
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256
#   runtime          = "python3.12"
#   handler          = "scheduler.handler"
#   tags             = merge(local.common_tags, { Name = "${var.project}-scheduler" })
#
# ── Lambda Permission ──
#   statement_id  = "AllowEventBridgeSchedule"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.scheduler.function_name
#   principal     = "events.amazonaws.com"
#   source_arn    = aws_cloudwatch_event_rule.schedule.arn
#   # ⚠️ source_arn 指定特定 Rule，防止其他 Rule 也能觸發這個 Lambda

resource "aws_lambda_function" "scheduler" {
  # TODO
  function_name    = "${var.project}-scheduler"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  handler          = "scheduler.handler"
  tags             = merge(local.common_tags, { Name = "${var.project}-scheduler" })
}

resource "aws_lambda_permission" "scheduler" {
  # TODO
  statement_id  = "AllowEventBridgeSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}


#--------------------------------------------------------------
# TODO 2: Schedule Rule + Target
#--------------------------------------------------------------
# 文件（rule）:   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule
# 文件（target）: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target
#
# ── Schedule Rule ──
#   name                = "${var.project}-schedule"
#   description         = "每 2 分鐘觸發一次"
#   schedule_expression = var.schedule_expression
#   state               = "ENABLED"
#   tags                = local.common_tags
#
#   schedule_expression 格式：
#     rate(2 minutes)         → 每 2 分鐘
#     rate(1 hour)            → 每小時（注意：1 用單數，2+ 用複數）
#     cron(0 9 ? * MON-FRI *) → 每週一到五早上 9 點 UTC
#
# ⚠️ Schedule Rule 不需要設定 event_bus_name，排程觸發走的是預設 bus 的特殊機制。
#
# ── Target ──
#   rule      = aws_cloudwatch_event_rule.schedule.name
#   target_id = "SchedulerLambda"
#   arn       = aws_lambda_function.scheduler.arn

resource "aws_cloudwatch_event_rule" "schedule" {
  # TODO
  name                = "${var.project}-schedule"
  description         = "每 2 分鐘觸發一次"
  schedule_expression = var.schedule_expression
  state               = "ENABLED"
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "schedule_lambda" {
  # TODO
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "SchedulerLambda"
  arn       = aws_lambda_function.scheduler.arn
}


#--------------------------------------------------------------
# TODO 3: Custom Event Bus
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_bus
#
# Default Event Bus（每個帳號都有）接收 AWS 服務事件（EC2, S3, RDS 等）。
# Custom Event Bus 接收你自己 put-events 的自訂事件，和 AWS 服務事件隔離。
#
# 好處：
#   - 不同應用、不同環境可以有獨立的 Event Bus
#   - 可以設定跨帳號事件接收（進階）
#
# 需要設定：
#   name = "${var.project}-bus"
#   tags = local.common_tags

resource "aws_cloudwatch_event_bus" "custom" {
  # TODO
  name = "${var.project}-bus"
  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 4: Lambda（事件處理器）+ Lambda Permission
#--------------------------------------------------------------
# 這個 Lambda 處理從 Custom Event Bus 路由過來的自訂事件。
# Permission 的 source_arn 指向 Pattern Rule（不是 Schedule Rule）。
#
# ── Lambda Function ──
#   function_name    = "${var.project}-processor"
#   role             = aws_iam_role.lambda.arn
#   filename         = data.archive_file.lambda_zip.output_path
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256
#   runtime          = "python3.12"
#   handler          = "processor.handler"
#   tags             = merge(local.common_tags, { Name = "${var.project}-processor" })
#
# ── Lambda Permission ──
#   statement_id  = "AllowEventBridgePattern"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.processor.function_name
#   principal     = "events.amazonaws.com"
#   source_arn    = aws_cloudwatch_event_rule.pattern.arn

resource "aws_lambda_function" "processor" {
  # TODO
  function_name    = "${var.project}-processor"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  handler          = "processor.handler"
  tags             = merge(local.common_tags, { Name = "${var.project}-processor" })
}

resource "aws_lambda_permission" "processor" {
  # TODO
  statement_id  = "AllowEventBridgePattern"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.pattern.arn
}


#--------------------------------------------------------------
# TODO 5: Event Pattern Rule + Target
#--------------------------------------------------------------
# 文件（rule）:   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule
# 文件（target）: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target
#
# ── Event Pattern Rule ──
#   name           = "${var.project}-pattern"
#   description    = "捕捉 myapp.orders 的 order.created 事件（status=pending 或 confirmed）"
#   event_bus_name = aws_cloudwatch_event_bus.custom.name   # ← 指定 Custom Bus
#   state          = "ENABLED"
#   tags           = local.common_tags
#
#   event_pattern = jsonencode({
#     source      = ["myapp.orders"]         # 必須完全符合
#     detail-type = ["order.created"]        # 必須完全符合
#     detail = {
#       status = ["pending", "confirmed"]    # detail 欄位的值必須在清單中
#     }
#   })
#
# ⚠️ event_pattern 的每個條件是 AND 關係，清單內是 OR 關係：
#    以上條件 = source 是 myapp.orders
#              AND detail-type 是 order.created
#              AND detail.status 是 pending 或 confirmed
#
# ── Target ──
#   rule           = aws_cloudwatch_event_rule.pattern.name
#   event_bus_name = aws_cloudwatch_event_bus.custom.name   # ← Target 也要指定同一個 Bus
#   target_id      = "ProcessorLambda"
#   arn            = aws_lambda_function.processor.arn

resource "aws_cloudwatch_event_rule" "pattern" {
  # TODO
  name           = "${var.project}-pattern"
  description    = "捕捉 myapp.orders 的 order.created 事件（status=pending 或 confirmed）"
  event_bus_name = aws_cloudwatch_event_bus.custom.name
  state          = "ENABLED"
  tags           = local.common_tags
  event_pattern = jsonencode({
    source      = ["myapp.orders"]
    detail-type = ["order.created"]
    detail = {
      status = ["pending", "confirmed"]
    }
  })
}

resource "aws_cloudwatch_event_target" "pattern_lambda" {
  # TODO
  rule           = aws_cloudwatch_event_rule.pattern.name
  event_bus_name = aws_cloudwatch_event_bus.custom.name
  target_id      = "ProcessorLambda"
  arn            = aws_lambda_function.processor.arn
}
