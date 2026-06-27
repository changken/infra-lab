output "resource_group_name" {
  description = "Resource Group 名稱"
  value       = azurerm_resource_group.rg.name
}

output "container_app_name" {
  description = "Container App 名稱"
  value       = azurerm_container_app.app.name
}

output "app_url" {
  description = "Container App 對外 URL（https://xxx.xxx.azurecontainerapps.io）"
  value       = "https://${azurerm_container_app.app.latest_revision_fqdn}"
}
