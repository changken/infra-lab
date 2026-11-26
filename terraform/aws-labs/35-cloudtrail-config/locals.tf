locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "35-cloudtrail-config"
    ManagedBy   = "terraform"
  }
}
