locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "42-security-compliance"
    ManagedBy   = "terraform"
  }
}
