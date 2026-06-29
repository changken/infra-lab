locals {
  # DO 標籤為 list(string)
  tags = [
    "project:${var.project}",
    "env:${var.environment}",
    "managed-by:terraform",
  ]

  droplet_name = var.droplet_name != "" ? var.droplet_name : "${var.project}-${var.environment}"
}
