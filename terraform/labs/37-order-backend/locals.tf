locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "37-order-backend"
    ManagedBy   = "terraform"
  }
}
