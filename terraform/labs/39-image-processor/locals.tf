locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "39-image-processor"
    ManagedBy   = "terraform"
  }
}
