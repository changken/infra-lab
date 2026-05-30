#==============================================================
# 場景：圖片處理微服務
#
# 架構（事件驅動，EventBridge 作為事件匯流排）：
#
#   使用者 PUT image.jpg
#       │
#       ▼
#   S3 Input Bucket（eventbridge = true）
#       │ AWS EventBridge S3 Event（Object Created）
#       ▼
#   EventBridge Rule（過濾 source=aws.s3，bucket=input）
#       │
#       ▼
#   Lambda: processor（複製檔案 + 產生 metadata.json）
#       │ s3:PutObject
#       ▼
#   S3 Output Bucket（私有）
#       │
#       ▼
#   CloudFront Distribution（OAC 簽章存取）
#       │
#       ▼
#   使用者透過 CloudFront URL 取得處理後的圖片
#
# 與 Lab 09 的關鍵差異（面試常考）：
#   Lab 09：S3 直接觸發 Lambda（aws_s3_bucket_notification → lambda）
#           → 每個 Bucket 只能有 1 個 Lambda per event type
#           → 難以加入過濾邏輯或多個下游消費者
#   Lab 39：S3 → EventBridge → Lambda（eventbridge = true in notification）
#           → 一個事件可以 fan-out 到多個 Rule（多個消費者）
#           → Rule 支援複雜的 Pattern 過濾（prefix、suffix、content-type）
#           → EventBridge 有事件歷史，可 replay
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6
#==============================================================


# 已完成：基礎 Data Sources
data "aws_caller_identity" "current" {}

# 已完成：bucket 名稱需唯一 suffix
resource "random_id" "suffix" {
  byte_length = 4
}

# 已完成：打包 Lambda 原始碼
data "archive_file" "processor" {
  type        = "zip"
  source_file = "${path.module}/src/processor.py"
  output_path = "${path.module}/src/processor.zip"
}


#--------------------------------------------------------------
# TODO 1: S3 Input Bucket（上傳原始圖片）+ 啟用 EventBridge
#--------------------------------------------------------------
# 文件 (bucket):       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
# 文件 (public_block): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block
# 文件 (notification): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification
#
# [S3 Input Bucket]
#   bucket        = "${var.project}-input-${random_id.suffix.hex}"
#   force_destroy = true
#   tags          = local.common_tags
#
# [Public Access Block]（封鎖所有公開存取，使用者透過 aws s3 cp + IAM 上傳）
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
#
# [Bucket Notification]（關鍵：開啟 EventBridge 整合，僅需一個參數）
#   bucket      = aws_s3_bucket.input.id
#   eventbridge = true    ← 這一行讓 S3 把所有事件送到 EventBridge default event bus
#                           （Lab 09 是直接指定 Lambda ARN，這裡改為走 EventBridge）
#
# ⚠️ 注意：eventbridge = true 只是把 S3 事件「轉送」到 EventBridge
#          還需要 EventBridge Rule（TODO 5）來過濾並路由到 Lambda

resource "aws_s3_bucket" "input" {
  # TODO
  bucket        = "${var.project}-input-${random_id.suffix.hex}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "input" {
  # TODO
  bucket = aws_s3_bucket.input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "input" {
  # TODO
  bucket      = aws_s3_bucket.input.id
  eventbridge = true
}


#--------------------------------------------------------------
# TODO 2: S3 Output Bucket（存放處理後圖片，CloudFront 來源）
#--------------------------------------------------------------
# 文件: 同 TODO 1
#
# [S3 Output Bucket]
#   bucket        = "${var.project}-output-${random_id.suffix.hex}"
#   force_destroy = true
#   tags          = local.common_tags
#
# [Public Access Block]（完全私有，只允許 CloudFront OAC 存取）
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
#
# ⚠️ 注意：Output Bucket 完全私有
#          使用者不能直接存取 S3 URL，只能透過 CloudFront Distribution

resource "aws_s3_bucket" "output" {
  # TODO
  bucket        = "${var.project}-output-${random_id.suffix.hex}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "output" {
  # TODO
  bucket = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


#--------------------------------------------------------------
# TODO 3: Lambda IAM Role + Policy
#--------------------------------------------------------------
# 文件 (role):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
# 文件 (attach): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
# 文件 (policy): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
#
# [IAM Role]
#   name = "${var.project}-processor-role"
#   assume_role_policy: Principal.Service = "lambda.amazonaws.com"
#
# [Policy Attachment]（CloudWatch Logs 寫入）
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
#
# [Inline Policy]（最小權限：讀 Input + 寫 Output）
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect   = "Allow"
#         Action   = ["s3:GetObject"]
#         Resource = "${aws_s3_bucket.input.arn}/*"   ← 只讀 Input Bucket
#       },
#       {
#         Effect   = "Allow"
#         Action   = ["s3:PutObject"]
#         Resource = "${aws_s3_bucket.output.arn}/*"  ← 只寫 Output Bucket
#       }
#     ]
#   })
#
# ⚠️ 注意：兩個 S3 Bucket 的 ARN 分別授權，不用 * 資源（最小權限）

resource "aws_iam_role" "processor" {
  # TODO
  name = "${var.project}-processor-role"
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
}

resource "aws_iam_role_policy_attachment" "processor_basic" {
  # TODO
  role       = aws_iam_role.processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "processor_s3" {
  # TODO
  name = "${var.project}-processor-s3-policy"
  role = aws_iam_role.processor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.input.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.output.arn}/*"
      }
    ]
  })
}


#--------------------------------------------------------------
# TODO 4: Lambda Function + EventBridge Permission
#--------------------------------------------------------------
# 文件 (lambda):     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
# 文件 (permission): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission
#
# [Lambda Function]
#   function_name    = "${var.project}-processor"
#   role             = aws_iam_role.processor.arn
#   handler          = "processor.lambda_handler"
#   runtime          = "python3.13"
#   filename         = data.archive_file.processor.output_path
#   source_code_hash = data.archive_file.processor.output_base64sha256
#   timeout          = 30
#   tags             = local.common_tags
#
#   environment {
#     variables = {
#       OUTPUT_BUCKET = aws_s3_bucket.output.id
#     }
#   }
#
# [Lambda Permission]（允許 EventBridge 觸發此 Lambda）
#   statement_id  = "AllowEventBridgeInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.processor.function_name
#   principal     = "events.amazonaws.com"          ← EventBridge 的 principal（非 s3.amazonaws.com）
#   source_arn    = aws_cloudwatch_events_rule.s3_upload.arn
#
# ⚠️ 注意：EventBridge 的 principal 是 "events.amazonaws.com"
#          Lab 09 的 S3 直接觸發是 "s3.amazonaws.com"，兩者不同

resource "aws_lambda_function" "processor" {
  # TODO
  function_name    = "${var.project}-processor"
  role             = aws_iam_role.processor.arn
  handler          = "processor.lambda_handler"
  runtime          = "python3.13"
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  timeout          = 30
  tags             = local.common_tags

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output.id
    }
  }
}

resource "aws_lambda_permission" "eventbridge" {
  # TODO
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_upload.arn
}


#--------------------------------------------------------------
# TODO 5: EventBridge Rule + Target（S3 Upload → Lambda）
#--------------------------------------------------------------
# 文件 (rule):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule
# 文件 (target): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target
#
# [EventBridge Rule]（過濾 S3 Input Bucket 的 Object Created 事件）
#   name        = "${var.project}-s3-upload"
#   description = "Trigger processor Lambda when file is uploaded to input bucket"
#
#   event_pattern = jsonencode({
#     source      = ["aws.s3"]
#     detail-type = ["Object Created"]          ← 注意 key 有 hyphen，需用引號
#     detail = {
#       bucket = {
#         name = [aws_s3_bucket.input.id]       ← 只監聽 Input Bucket，不監聽 Output Bucket
#       }
#     }
#   })
#   tags = local.common_tags
#
# [EventBridge Target]（Lambda 作為目標）
#   rule      = aws_cloudwatch_events_rule.s3_upload.name
#   target_id = "ProcessorLambda"
#   arn       = aws_lambda_function.processor.arn
#
# ⚠️ 注意：event_pattern 的 detail.bucket.name 必須是 Array（即使只有一個值）
#          若不過濾 bucket name，所有 S3 bucket 的事件都會觸發此 Rule！

resource "aws_cloudwatch_event_rule" "s3_upload" {
  # TODO
  name        = "${var.project}-s3-upload"
  description = "Trigger processor Lambda when file is uploaded to input bucket"
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.input.id]
      }
    }
  })
  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "processor_lambda" {
  # TODO
  rule      = aws_cloudwatch_event_rule.s3_upload.name
  target_id = "ProcessorLambda"
  arn       = aws_lambda_function.processor.arn
}


#--------------------------------------------------------------
# TODO 6: CloudFront OAC + Distribution + S3 Bucket Policy
#--------------------------------------------------------------
# 文件 (oac):          https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control
# 文件 (distribution): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution
# 文件 (bucket_policy): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy
#
# [CloudFront OAC]（現代方式，取代已棄用的 OAI）
#   name                              = "${var.project}-oac"
#   origin_access_control_origin_type = "s3"
#   signing_behavior                  = "always"
#   signing_protocol                  = "sigv4"
#
# [CloudFront Distribution]
#   enabled             = true
#   default_root_object = ""       ← 圖片服務不需要 index.html
#   price_class         = "PriceClass_100"   ← 只用北美 + 歐洲 Edge（最省錢）
#   tags                = local.common_tags
#
#   origin {
#     domain_name              = aws_s3_bucket.output.bucket_regional_domain_name  ← 必須用 regional
#     origin_id                = "S3OutputBucket"
#     origin_access_control_id = aws_cloudfront_origin_access_control.main.id
#   }
#
#   default_cache_behavior {
#     target_origin_id       = "S3OutputBucket"
#     viewer_protocol_policy = "redirect-to-https"
#     allowed_methods        = ["GET", "HEAD"]
#     cached_methods         = ["GET", "HEAD"]
#     compress               = true
#
#     forwarded_values {
#       query_string = false
#       cookies { forward = "none" }
#     }
#
#     min_ttl     = 0
#     default_ttl = 3600
#     max_ttl     = 86400
#   }
#
#   restrictions {
#     geo_restriction { restriction_type = "none" }
#   }
#
#   viewer_certificate {
#     cloudfront_default_certificate = true   ← 使用 *.cloudfront.net 預設憑證
#   }
#
# [S3 Bucket Policy]（只允許來自此 CloudFront Distribution 的請求）
#   bucket = aws_s3_bucket.output.id
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Sid    = "AllowCloudFrontOAC"
#       Effect = "Allow"
#       Principal = { Service = "cloudfront.amazonaws.com" }
#       Action    = "s3:GetObject"
#       Resource  = "${aws_s3_bucket.output.arn}/*"
#       Condition = {
#         StringEquals = {
#           "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
#         }
#       }
#     }]
#   })
#
# ⚠️ 注意：Condition 的 "AWS:SourceArn" 必須鎖定到特定 Distribution ARN
#          若省略 Condition，同帳號其他 CloudFront Distribution 也能讀這個 Bucket
#
# ⚠️ 注意：CloudFront Distribution 建立需要約 5-10 分鐘，state 變為 Deployed 才能使用

resource "aws_cloudfront_origin_access_control" "main" {
  # TODO
  name                              = "${var.project}-cf-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  # TODO
  enabled             = true
  default_root_object = ""
  price_class         = "PriceClass_100"
  tags                = local.common_tags

  origin {
    # TODO
    domain_name              = aws_s3_bucket.output.bucket_regional_domain_name
    origin_id                = "S3OutputBucket"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  default_cache_behavior {
    # TODO
    target_origin_id       = "S3OutputBucket"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      # TODO
      query_string = false
      cookies {
        # TODO
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      # TODO
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # TODO
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket_policy" "output_cloudfront" {
  # TODO
  bucket = aws_s3_bucket.output.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.output.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}
