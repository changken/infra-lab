locals {
  common_tags = {
    Project     = "infra-lab"
    Module      = "aws-windows"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
