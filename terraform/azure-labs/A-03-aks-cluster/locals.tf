locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = "${local.name_prefix}-aks"
}
