locals {
  # Hetzner 標籤為 map(string)
  labels = {
    project    = var.project
    env        = var.environment
    managed-by = "terraform"
  }
}
