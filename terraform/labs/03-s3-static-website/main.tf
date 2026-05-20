#==============================================================
# 學習目標：用 S3 架一個對外的靜態網站
#
# 架構：
#
#   使用者瀏覽器
#       │
#       │  HTTP
#       ▼
#   ┌─────────────────────────┐
#   │  S3 Bucket              │
#   │  (Website Endpoint)     │
#   │                         │
#   │  ├── index.html         │
#   │  └── error.html         │
#   │                         │
#   │  Policy: PublicRead     │
#   │  Website Config 開啟    │
#   └─────────────────────────┘
#
# 重要觀念：
#   - S3 bucket 名稱「全球唯一」(不只你的帳號，是全 AWS)
#   - 2023 後 AWS 預設擋掉所有 public access，要主動「開洞」
#   - 開洞要 4 個布林值 + 1 個 bucket policy 都對才行
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6
#==============================================================


#--------------------------------------------------------------
# 0: Random suffix (已完成，給你看 random provider 怎麼用)
#--------------------------------------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4   # 產生 8 個 hex 字元
}


#--------------------------------------------------------------
# TODO 1: S3 Bucket
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
#
# 需要設定的屬性：
#   - bucket  → 用 local.bucket_name
#   - tags
#
# 注意：bucket 屬性是「名字」，不是 ID。

resource "aws_s3_bucket" "site" {
  # TODO
  bucket = local.bucket_name
  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-site" })
}


#--------------------------------------------------------------
# TODO 2: Public Access Block（這是「開洞」的關鍵）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block
#
# AWS 預設 4 個值都是 true（完全擋住 public）。
# 靜態網站要對外，要把這 4 個都設成 false。
#
# 需要設定的屬性：
#   - bucket                  → aws_s3_bucket.site.id
#   - block_public_acls       → false
#   - block_public_policy     → false
#   - ignore_public_acls      → false
#   - restrict_public_buckets → false
#
# ⚠️ 真實環境只有「靜態網站 bucket」這樣設，存資料的 bucket 千萬別跟著做。

resource "aws_s3_bucket_public_access_block" "site" {
  # TODO
  bucket = aws_s3_bucket.site.id
  block_public_acls = false
  block_public_policy = false
  ignore_public_acls = false
  restrict_public_buckets = false
}


#--------------------------------------------------------------
# TODO 3: Bucket Policy（允許所有人讀取）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy
#
# 需要設定的屬性：
#   - bucket  → aws_s3_bucket.site.id
#   - policy  → 一段 JSON（下面用 jsonencode 寫）
#
# 這個 policy 已經寫好了，你只要把它放進對的 resource block：
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid       = "PublicReadGetObject"
#         Effect    = "Allow"
#         Principal = "*"
#         Action    = "s3:GetObject"
#         Resource  = "${aws_s3_bucket.site.arn}/*"
#       }
#     ]
#   })
#
# ⚠️ 這個 resource 必須在 TODO 2（public_access_block）之後 apply，
#    否則會被 AWS 擋下來。Terraform 通常會自動排序，但偶爾要手動加
#    depends_on = [aws_s3_bucket_public_access_block.site]

resource "aws_s3_bucket_policy" "site" {
  # TODO
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
     Version = "2012-10-17"
     Statement = [
       {
         Sid       = "PublicReadGetObject"
         Effect    = "Allow"
         Principal = "*"
         Action    = "s3:GetObject"
         Resource  = "${aws_s3_bucket.site.arn}/*"
       }
     ]
   })
   depends_on = [aws_s3_bucket_public_access_block.site]
}


#--------------------------------------------------------------
# TODO 4: Website Configuration
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_website_configuration
#
# 需要設定的屬性：
#   - bucket  → aws_s3_bucket.site.id
#   - index_document 區塊：
#       suffix = var.index_document
#   - error_document 區塊：
#       key = var.error_document

resource "aws_s3_bucket_website_configuration" "site" {
  # TODO
  bucket = aws_s3_bucket.site.id
  index_document {
    suffix = var.index_document
  }
  error_document {
    key = var.error_document
  }
}


#--------------------------------------------------------------
# TODO 5: 上傳 index.html
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
#
# 需要設定的屬性：
#   - bucket        → aws_s3_bucket.site.id
#   - key           → var.index_document
#   - source        → "${path.module}/website/index.html"
#   - content_type  → "text/html"
#   - etag          → filemd5("${path.module}/website/index.html")
#                     （etag 是用來偵測檔案變更，沒寫的話改 HTML 不會 re-upload）

resource "aws_s3_object" "index" {
  # TODO
  bucket = aws_s3_bucket.site.id
  key = var.index_document
  source = "${path.module}/website/index.html"
  content_type = "text/html"
  etag = filemd5("${path.module}/website/index.html")
}


#--------------------------------------------------------------
# TODO 6: 上傳 error.html
#--------------------------------------------------------------
# 跟 TODO 5 一樣的寫法，把檔名換成 error.html

resource "aws_s3_object" "error" {
  # TODO
  bucket = aws_s3_bucket.site.id
  key = var.error_document
  source = "${path.module}/website/error.html"
  content_type = "text/html"
  etag = filemd5("${path.module}/website/error.html")
}
