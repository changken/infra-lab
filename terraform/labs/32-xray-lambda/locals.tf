locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "32-xray-lambda"
    ManagedBy   = "terraform"
  }
}
