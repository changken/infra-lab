locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "38-cicd-pipeline"
    ManagedBy   = "terraform"
  }
}
