locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Lab         = "03-s3-static-website"
  }

  # 用 random_id 產生全球唯一 bucket 名
  # （S3 bucket name 全球唯一，這是新手最常踩的雷）
  bucket_name = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
}
