locals {
  common_tags = {
    Project     = "infra-lab"
    Module      = "aws-linux"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
