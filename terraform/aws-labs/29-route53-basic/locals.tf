locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "29-route53-basic"
    ManagedBy   = "terraform"
  }

  # Private Hosted Zone 的域名，.internal 是業界慣例（非保留字，但不會和公開域名衝突）
  zone_name = "${var.project}.internal"
}
