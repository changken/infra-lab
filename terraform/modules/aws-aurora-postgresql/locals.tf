#==============================================================
# AWS Aurora PostgreSQL Module - Local Variables
#==============================================================

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
