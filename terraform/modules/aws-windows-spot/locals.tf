locals {
  common_tags = {
    Project     = "infra-lab"
    Module      = "aws-windows-spot"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
