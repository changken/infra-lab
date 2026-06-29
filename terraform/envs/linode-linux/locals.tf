locals {
  # Linode 標籤為 list(string)
  tags = [
    "project:${var.project}",
    "env:${var.environment}",
    "managed-by:terraform",
  ]
}
