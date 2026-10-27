output "resource_group_name" {
  description = "Resource Group 名稱"
  value       = azurerm_resource_group.avd.name
}

output "vnet_id" {
  description = "VNet ID"
  value       = azurerm_virtual_network.avd.id
}

output "host_pool_name" {
  description = "AVD Host Pool 名稱"
  value       = azurerm_virtual_desktop_host_pool.avd.name
}

output "workspace_name" {
  description = "AVD Workspace 名稱"
  value       = azurerm_virtual_desktop_workspace.avd.name
}

output "app_group_name" {
  description = "AVD Application Group 名稱"
  value       = azurerm_virtual_desktop_application_group.avd.name
}

output "session_host_private_ips" {
  description = "Session Host VM(s) 私有 IP"
  value       = [for nic in azurerm_network_interface.session_host : nic.ip_configuration[0].private_ip_address]
}

output "avd_web_client_url" {
  description = "AVD 網頁版客戶端登入網址"
  value       = "https://client.wvd.microsoft.com/arm/webclient"
}

output "connection_guide" {
  description = "AVD 連線指引"
  value       = <<-EOT
    ┌─────────────────────────────────────────────────────────────┐
    │  AVD 桌面連線步驟                                            │
    ├─────────────────────────────────────────────────────────────┤
    │  1. 網頁版登入：                                            │
    │     開啟瀏覽器前往: https://client.wvd.microsoft.com/arm/webclient
    │     使用具有權限的 Microsoft Entra ID 帳號登入              │
    │                                                             │
    │  2. 桌面客戶端（推薦）：                                     │
    │     下載 Windows App / Remote Desktop Client                │
    │     點擊「訂閱 (Subscribe)」並登入 Azure 帳號              │
    │                                                             │
    │  3. 看到「${azurerm_virtual_desktop_application_group.avd.friendly_name}」圖示點擊即可開啟遠端桌面！ │
    └─────────────────────────────────────────────────────────────┘
  EOT
}
