locals {
  prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "45-kinesis-data-streams"
    ManagedBy   = "terraform"
  }
}
