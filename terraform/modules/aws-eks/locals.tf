locals {
  name_prefix = "${var.project}-${var.environment}"
  is_ec2      = var.compute_mode == "ec2"
  is_fargate  = var.compute_mode == "fargate"

  node_subnet_ids    = length(var.node_subnet_ids) > 0 ? var.node_subnet_ids : var.subnet_ids
  fargate_subnet_ids = length(var.fargate_subnet_ids) > 0 ? var.fargate_subnet_ids : var.subnet_ids

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}
