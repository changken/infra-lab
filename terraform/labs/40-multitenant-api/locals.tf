locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "40-multitenant-api"
    ManagedBy   = "terraform"
  }
}
