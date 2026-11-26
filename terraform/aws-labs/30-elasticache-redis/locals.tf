locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "30-elasticache-redis"
    ManagedBy   = "terraform"
  }
}
