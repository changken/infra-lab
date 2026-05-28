locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "43-terraform-modules"
    ManagedBy   = "terraform"
  }
}
