locals {
  common_tags = {
    Project     = "infra-lab"
    Module      = "azure-windows"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  use_generated_password = var.admin_password == null
  effective_password     = local.use_generated_password ? random_password.win[0].result : var.admin_password
}
