locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "48-aurora-windows-bastion"
    ManagedBy   = "terraform"
  }
}
