locals {
  rg       = azurerm_resource_group.avd.name
  location = azurerm_resource_group.avd.location

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
