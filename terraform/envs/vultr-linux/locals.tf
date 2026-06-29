locals {
  # Vultr 標籤為 list(string)，格式：key:value
  tags = [
    "project:${var.project}",
    "env:${var.environment}",
    "managed-by:terraform",
  ]

  instance_label = "${var.project}-${var.environment}"
}
