locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  name_prefix = "${var.project}-${var.environment}"

  # ACR 名稱只能英數、全域唯一、3-50 字元
  # 用 random suffix 避免衝突（類似 S3 bucket 全域唯一的問題）
  acr_name = replace("${local.name_prefix}acr", "-", "")
}
