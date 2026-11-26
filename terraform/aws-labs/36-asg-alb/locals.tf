locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "36-asg-alb"
    ManagedBy   = "terraform"
  }
}
