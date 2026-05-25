locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "31-cognito-userpool"
    ManagedBy   = "terraform"
  }
}
