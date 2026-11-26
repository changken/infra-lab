locals {
  prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "44-step-functions"
    ManagedBy   = "terraform"
  }
}
