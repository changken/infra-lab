output "resource_group_name" {
  description = "Name of the Resource Group"
  value       = local.rg_name
}

output "resource_group_location" {
  description = "Location of the Resource Group"
  value       = local.rg_location
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.vnet.name
}

output "public_subnet_ids" {
  description = "Map of public subnet name => subnet ID"
  value       = { for k, v in azurerm_subnet.public : k => v.id }
}

output "private_subnet_ids" {
  description = "Map of private subnet name => subnet ID"
  value       = { for k, v in azurerm_subnet.private : k => v.id }
}

output "public_nsg_id" {
  description = "ID of the public Network Security Group"
  value       = azurerm_network_security_group.public.id
}

output "private_nsg_id" {
  description = "ID of the private Network Security Group"
  value       = azurerm_network_security_group.private.id
}
