locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "28-cloudfront-s3"
    ManagedBy   = "terraform"
  }
}
