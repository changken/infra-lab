locals {
  common_tags = {
    Project     = "infra-lab"
    Module      = "azure-vnet"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  rg_name     = var.create_resource_group ? azurerm_resource_group.rg[0].name : var.resource_group_name
  rg_location = var.create_resource_group ? azurerm_resource_group.rg[0].location : var.location
}
