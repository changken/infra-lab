locals {
  common_tags = {
    Project     = "infra-lab"
    Module      = "azure-linux"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  use_generated_key    = var.admin_ssh_public_key == null
  effective_public_key = local.use_generated_key ? tls_private_key.linux[0].public_key_openssh : var.admin_ssh_public_key
}
