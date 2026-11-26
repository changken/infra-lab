locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "33-secrets-manager"
    ManagedBy   = "terraform"
  }
}
