output "acr_name" {
  description = "ACR 名稱（全域唯一）"
  # TODO: azurerm_container_registry.acr 的 name attribute
  value = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  description = "ACR login server（docker push 用）e.g. acrdevacr.azurecr.io"
  # TODO: azurerm_container_registry.acr 的 login_server attribute
  value = azurerm_container_registry.acr.login_server
}

output "admin_username" {
  description = "ACR admin 帳號（admin_enabled = true 時才有）"
  # TODO: azurerm_container_registry.acr 的 admin_username attribute
  value     = azurerm_container_registry.acr.admin_username
  sensitive = true
}

output "admin_password" {
  description = "ACR admin 密碼"
  # TODO: azurerm_container_registry.acr 的 admin_password attribute
  value     = azurerm_container_registry.acr.admin_password
  sensitive = true
}

output "docker_login_cmd" {
  description = "登入 ACR 的指令（複製後直接跑）"
  # TODO: 組合成 "docker login <login_server> -u <admin_username>" 的字串
  value     = "docker login ${azurerm_container_registry.acr.login_server} -u ${azurerm_container_registry.acr.admin_username} -p ${azurerm_container_registry.acr.admin_password}"
  sensitive = true
}
