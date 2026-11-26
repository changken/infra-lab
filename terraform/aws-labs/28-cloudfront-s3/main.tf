#==============================================================
# 學習目標：CloudFront + S3 靜態網站（OAC 取代 OAI）
#
# 核心問題：如何讓 S3 Bucket 完全私有，卻又能透過 CDN 公開網站？
#
# 舊方法（OAI - Origin Access Identity）：
#   已於 2022 年被 AWS 標示為「建議停止使用」
#   設定複雜，不支援 Server-Side Encryption with KMS
#
# 新方法（OAC - Origin Access Control）：
#   更細粒度的控制（可限定 HTTP method）
#   支援 KMS 加密的 S3 Bucket
#   支援所有 S3 地區（OAI 在某些新地區有問題）
#
# 流程：
#   使用者 → CloudFront Edge（全球）
#                 │  CloudFront 用 SigV4 簽署請求
#                 ▼
#              S3 Bucket（完全私有，無 Public Access）
#                 │  Bucket Policy 只允許來自此 CloudFront Distribution 的請求
#                 └─ 確保繞過 CloudFront 直連 S3 會被拒絕
#
# 新概念：
#   aws_cloudfront_origin_access_control → OAC 資源，定義 S3 的存取方式
#   bucket_regional_domain_name          → 必須用 Regional 域名，不能用舊的 bucket_domain_name
#   custom_error_response                → OAC 下 S3 對不存在的檔案回傳 403，需要 mapping 到 error.html
#   CloudFront Invalidation              → 更新 S3 檔案後，需要 invalidate 快取才能看到新版本
#
# ⚠️ 安全關鍵：
#   Bucket Policy 的 Condition 要鎖定到特定 Distribution ARN，
#   否則同帳號其他 CloudFront Distribution 也能存取這個 S3。
#
# 完成順序：1 → 2 → 3 → 4 → 5
#==============================================================


# 已完成：取得帳號資訊
data "aws_caller_identity" "current" {}

# 已完成：隨機 suffix，確保 bucket name 全球唯一
resource "random_id" "suffix" {
  byte_length = 4
}

# 已完成：S3 Bucket（私有儲存桶）
resource "aws_s3_bucket" "website" {
  bucket = "${var.project}-website-${random_id.suffix.hex}"
  tags   = local.common_tags
}


#--------------------------------------------------------------
# TODO 1: S3 Block Public Access（封鎖所有公開存取）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block
#
# S3 Bucket 必須完全私有，使用者只能透過 CloudFront 存取。
# 把以下四個選項全設為 true：
#
#   bucket = aws_s3_bucket.website.id
#
#   block_public_acls       = true   # 封鎖新增公開 ACL
#   block_public_policy     = true   # 封鎖公開 Bucket Policy
#   ignore_public_acls      = true   # 忽略已存在的公開 ACL
#   restrict_public_buckets = true   # 限制公開 Bucket

resource "aws_s3_bucket_public_access_block" "website" {
  # TODO
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

}


#--------------------------------------------------------------
# TODO 2: S3 Bucket Policy（只允許 CloudFront OAC 存取）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy
#
# 這是 OAC 的關鍵設定，Bucket Policy 決定哪個 CloudFront Distribution 可以讀 S3。
#
#   bucket = aws_s3_bucket.website.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Sid    = "AllowCloudFrontServicePrincipal"
#       Effect = "Allow"
#       Principal = {
#         Service = "cloudfront.amazonaws.com"
#         # ← 不是 IAM Role，是 CloudFront 服務本身
#       }
#       Action   = "s3:GetObject"
#       Resource = "${aws_s3_bucket.website.arn}/*"
#       Condition = {
#         StringEquals = {
#           "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
#           # ← 鎖定到特定 Distribution，防止其他 CloudFront 也能存取
#         }
#       }
#     }]
#   })
#
# ⚠️ depends_on：Bucket Policy 引用了 aws_cloudfront_distribution.website.arn，
#    Terraform 會自動推算依賴，但明確加上 depends_on 讓意圖更清晰。

resource "aws_s3_bucket_policy" "website" {
  # TODO
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontServicePrincipal"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.website.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
        }
      }
    }]
  })

}


#--------------------------------------------------------------
# TODO 3: CloudFront OAC（Origin Access Control）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control
#
# OAC 是一個「簽名設定」，告訴 CloudFront 用 SigV4 簽名存取 S3。
#
#   name                              = "${var.project}-oac"
#   description                       = "OAC for ${aws_s3_bucket.website.id}"
#   origin_access_control_origin_type = "s3"
#   # ← 目前只支援 s3，未來可能支援其他 origin type
#
#   signing_behavior = "always"
#   # ← always：每個請求都簽名
#   # ← never：不簽名（等同不用 OAC）
#   # ← no-override：origin 有 Auth header 就不覆蓋
#
#   signing_protocol = "sigv4"
#   # ← 目前只有 sigv4，固定填這個

resource "aws_cloudfront_origin_access_control" "website" {
  # TODO
  name                              = "${var.project}-oac"
  description                       = "OAC for ${aws_s3_bucket.website.id}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


#--------------------------------------------------------------
# TODO 4: CloudFront Distribution
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution
#
# CloudFront Distribution 是整個 CDN 設定的核心。
#
#   enabled             = true
#   default_root_object = "index.html"
#   # ← 瀏覽 https://your-cf-domain/ 時自動回傳 index.html
#
#   tags = local.common_tags
#
#   # --- Origin（從哪裡取內容）---
#   origin {
#     domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
#     # ⚠️ 必須用 bucket_regional_domain_name，不能用 bucket_domain_name
#     # bucket_domain_name 是舊格式（全球域名），OAC 要求用區域域名
#
#     origin_id                = "S3-${aws_s3_bucket.website.id}"
#     # ← 自訂 ID，在 cache behavior 的 target_origin_id 要對應這個值
#
#     origin_access_control_id = aws_cloudfront_origin_access_control.website.id
#     # ← 掛上 OAC，讓 CloudFront 用 SigV4 存取 S3
#   }
#
#   # --- Default Cache Behavior（如何快取）---
#   default_cache_behavior {
#     target_origin_id       = "S3-${aws_s3_bucket.website.id}"
#     viewer_protocol_policy = "redirect-to-https"
#     # ← http 自動 redirect 到 https
#
#     allowed_methods = ["GET", "HEAD"]
#     cached_methods  = ["GET", "HEAD"]
#
#     forwarded_values {
#       query_string = false
#       cookies { forward = "none" }
#     }
#
#     min_ttl     = 0
#     default_ttl = 3600    # 1 小時
#     max_ttl     = 86400   # 24 小時
#   }
#
#   # --- Custom Error Response（OAC 特有問題的處理）---
#   # ⚠️ OAC 下，S3 對不存在的物件回傳 403（不是 404）
#   # 因為 CloudFront 沒有列出 bucket 內容的權限，S3 無法區分「沒權限」和「不存在」
#   # 所以要把 403 mapping 到自訂的 error.html
#   custom_error_response {
#     error_code            = 403
#     response_code         = 404
#     response_page_path    = "/error.html"
#     error_caching_min_ttl = 10
#   }
#
#   # --- Geo Restriction（地理限制）---
#   restrictions {
#     geo_restriction {
#       restriction_type = "none"   # 全球開放
#     }
#   }
#
#   # --- SSL 憑證（使用 CloudFront 預設憑證，不需要自訂域名）---
#   viewer_certificate {
#     cloudfront_default_certificate = true
#   }

resource "aws_cloudfront_distribution" "website" {
  # TODO
  enabled             = true
  default_root_object = "index.html"
  tags                = local.common_tags

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.website.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.website.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/error.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


#--------------------------------------------------------------
# TODO 5: 上傳靜態檔案到 S3
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
#
# 把 www/ 目錄下的靜態檔案上傳到 S3。
# content_type 必須設定正確，否則瀏覽器不會渲染 HTML 而是下載。
#
# index.html：
#   bucket       = aws_s3_bucket.website.id
#   key          = "index.html"
#   source       = "${path.module}/www/index.html"
#   content_type = "text/html"
#   etag         = filemd5("${path.module}/www/index.html")
#   # ← etag 讓 Terraform 偵測檔案內容變化，自動重新上傳
#
# error.html：
#   bucket       = aws_s3_bucket.website.id
#   key          = "error.html"
#   source       = "${path.module}/www/error.html"
#   content_type = "text/html"
#   etag         = filemd5("${path.module}/www/error.html")

resource "aws_s3_object" "index" {
  # TODO
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "${path.module}/www/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/www/index.html")
}

resource "aws_s3_object" "error" {
  # TODO
  bucket       = aws_s3_bucket.website.id
  key          = "error.html"
  source       = "${path.module}/www/error.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/www/error.html")
}
