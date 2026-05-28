locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "41-observability-stack"
    ManagedBy   = "terraform"
  }
}
