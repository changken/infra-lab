locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Lab         = "02-custom-vpc-public-only"
  }
}
