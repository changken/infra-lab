locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = "${local.name_prefix}-eks"

  # cidrsubnet("10.0.0.0/16", 8, N) → 10.0.N.0/24
  public_subnet_cidrs = {
    for i, az in var.azs : az => cidrsubnet(var.vpc_cidr, 8, i + 1)
  }
  private_subnet_cidrs = {
    for i, az in var.azs : az => cidrsubnet(var.vpc_cidr, 8, i + 11)
  }

  # OIDC issuer URL without https:// prefix (used in IAM conditions)
  oidc_issuer = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
