#==============================================================
# 學習目標：S3 Event Trigger → Lambda
#
# 架構：
#   你上傳檔案到 S3
#     → S3 發出 ObjectCreated 事件
#         → Lambda 自動被觸發
#             → 讀取檔案內容，印到 CloudWatch log
#
# 新概念（跟前幾個 Lab 不同的地方）：
#   aws_s3_bucket_notification → 設定 S3 事件觸發 Lambda
#   Lambda Permission principal → 這次是 s3.amazonaws.com（不是 apigateway）
#   S3 GetObject 權限          → Lambda 要讀檔案內容，需要額外 IAM
#   depends_on 的重要性        → Notification 必須在 Permission 之後建立
#
# 完成順序：1 → 2 → 3 → 4
#==============================================================


# 已完成：zip 打包
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/processor.py"
  output_path = "${path.module}/src/processor.zip"
}

# 已完成：隨機 suffix（bucket 名稱需要全球唯一）
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 已完成：IAM Role
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
# TODO 1: S3 Bucket（私有，不需要公開存取）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
#
# 這個 bucket 是「上傳區」，不是靜態網站，所以不需要任何公開設定。
# 跟 Lab 03 最大的差異：這裡什麼 public access 設定都不需要加。
#
# 需要設定：
#   bucket = "${var.project}-uploads-${random_id.bucket_suffix.hex}"
#   tags   = merge(local.common_tags, { Name = "${var.project}-uploads" })

resource "aws_s3_bucket" "upload" {
  # TODO
  bucket = "${var.project}-uploads-${random_id.bucket_suffix.hex}"
  tags = merge(local.common_tags, { Name = "${var.project}-uploads" })
}


#--------------------------------------------------------------
# TODO 2: IAM Policy — 給 Lambda S3 GetObject 權限
#--------------------------------------------------------------
# Lambda 被觸發後要「讀取」剛上傳的檔案，需要 s3:GetObject 權限。
#
# 需要設定：
#   name = "s3-read"
#   role = aws_iam_role.lambda.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect   = "Allow"
#       Action   = ["s3:GetObject"]
#       Resource = "${aws_s3_bucket.upload.arn}/*"
#       # ⚠️ 注意：是 bucket ARN + "/*"，代表 bucket 內的所有物件
#     }]
#   })

resource "aws_iam_role_policy" "lambda_s3" {
  # TODO
  name = "s3-read"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.upload.arn}/*"
    }]
  })
}


#--------------------------------------------------------------
# TODO 3: Lambda Function
#--------------------------------------------------------------
# 跟前幾個 Lab 一樣的結構：
#
#   function_name    = var.function_name
#   role             = aws_iam_role.lambda.arn
#   filename         = data.archive_file.lambda_zip.output_path
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256
#   runtime          = "python3.12"
#   handler          = "processor.handler"   # ← 檔名是 processor.py
#   tags = merge(local.common_tags, { Name = var.function_name })

resource "aws_lambda_function" "processor" {
  # TODO
  function_name = var.function_name
  role = aws_iam_role.lambda.arn
  filename = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime = "python3.12"
  handler = "processor.handler"
  tags = merge(local.common_tags, { Name = var.function_name })
  depends_on = [aws_iam_role_policy.lambda_s3]  # 確保 IAM Policy 先建立
}


#--------------------------------------------------------------
# TODO 4: Lambda Permission + S3 Bucket Notification
#--------------------------------------------------------------
# 文件 (permission):    https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission
# 文件 (notification):  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification
#
# ── Lambda Permission（讓 S3 能觸發 Lambda） ──
#   statement_id  = "AllowS3Invoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.processor.function_name
#   principal     = "s3.amazonaws.com"          # ← 注意：跟 API Gateway 不同！
#   source_arn    = aws_s3_bucket.upload.arn     # ← 限定只有這個 bucket 能觸發
#
# ── S3 Bucket Notification（設定觸發條件） ──
#   bucket = aws_s3_bucket.upload.id
#
#   lambda_function {
#     lambda_function_arn = aws_lambda_function.processor.arn
#     events              = ["s3:ObjectCreated:*"]   # 任何新增物件都觸發
#     filter_prefix       = "uploads/"               # 只處理 uploads/ 前綴的檔案
#   }
#
#   depends_on = [aws_lambda_permission.s3]
#   # ⚠️ 必須等 Permission 建好，S3 才能驗證它有權呼叫 Lambda
#   #    少了這行 apply 可能成功，但實際觸發會失敗

resource "aws_lambda_permission" "s3" {
  # TODO
  statement_id = "AllowS3Invoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal = "s3.amazonaws.com"
  source_arn = aws_s3_bucket.upload.arn
}

resource "aws_s3_bucket_notification" "trigger" {
  # TODO
  bucket = aws_s3_bucket.upload.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }
  depends_on = [aws_lambda_permission.s3]
}
