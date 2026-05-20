#==============================================================
# 學習目標：建立 Lambda Function，理解 Serverless 的運作方式
#
# Lambda 執行需要的東西：
#   1. IAM Role      → Lambda 的身份（「我是誰」）
#   2. IAM Policy    → Lambda 能做什麼（「我能幹什麼」）
#   3. 程式碼 zip    → 打包成 zip 上傳
#   4. Lambda        → 主體（設定 runtime/handler/role）
#
# handler 格式：「檔名.函式名」
#   → hello.handler 意思是 src/hello.py 裡的 handler 函式
#
# 完成順序：1 → 2 → 3
#==============================================================


# 已完成：把 src/hello.py 打包成 zip（data source 不建立資源）
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/hello.py"
  output_path = "${path.module}/src/hello.zip"
}


#--------------------------------------------------------------
# TODO 1: IAM Role（Lambda 的執行身份）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# Lambda 需要一個 IAM Role，裡面的 assume_role_policy 告訴 AWS：
# 「允許 lambda.amazonaws.com 這個服務來扮演這個 Role」
#
# 需要設定：
#   name = "${var.function_name}-role"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "lambda.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
#
#   tags = local.common_tags

resource "aws_iam_role" "lambda" {
  # TODO
  name = "${var.function_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}


#--------------------------------------------------------------
# TODO 2: IAM Policy Attachment（給 Role 掛上 CloudWatch 權限）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
#
# Lambda 要寫 log 到 CloudWatch，需要掛上 AWS 內建的 Policy：
#   AWSLambdaBasicExecutionRole
#
# 需要設定：
#   role       = aws_iam_role.lambda.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  # TODO
  role = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


#--------------------------------------------------------------
# TODO 3: Lambda Function
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
#
# 需要設定：
#
# ── 身份 ──
#   function_name = var.function_name
#   role          = aws_iam_role.lambda.arn
#
# ── 程式碼 ──
#   filename         = data.archive_file.lambda_zip.output_path
#   source_code_hash = data.archive_file.lambda_zip.output_base64sha256
#   # source_code_hash 的作用：程式碼沒變就不重新上傳（類似 etag）
#
# ── 執行環境 ──
#   runtime = "python3.12"
#   handler = "hello.handler"   # 格式：「檔名.函式名」
#
# ── 環境變數 ──
#   environment {
#     variables = {
#       ENVIRONMENT = var.environment
#     }
#   }
#
# ── tags ──
#   tags = merge(local.common_tags, { Name = var.function_name })

resource "aws_lambda_function" "hello" {
  # TODO
  function_name = var.function_name 
  role = aws_iam_role.lambda.arn

  filename = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  runtime = "python3.12"
  handler = "hello.handler"

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = merge(local.common_tags, { Name = var.function_name })
}
