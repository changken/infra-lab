locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # 資源命名前綴（範例：aca-lab-dev）
  name_prefix = "${var.project}-${var.environment}"
}
