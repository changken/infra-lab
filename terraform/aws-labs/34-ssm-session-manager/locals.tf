locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "34-ssm-session-manager"
    ManagedBy   = "terraform"
  }
}
