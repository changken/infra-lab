locals {
  name_prefix = "${var.project}-${var.environment}"

  # cidrsubnet("10.1.0.0/16", 8, N) → 10.1.N.0/24
  public_subnet_cidrs = {
    for i, az in var.azs : az => cidrsubnet(var.vpc_cidr, 8, i + 1)
  }

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
