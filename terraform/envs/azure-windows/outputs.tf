output "windows_public_ip" {
  description = "Windows VM 公網 IP（用 RDP 連入）"
  value       = module.windows.public_ip
}

output "windows_private_ip" {
  description = "Windows VM 私有 IP"
  value       = module.windows.private_ip
}

output "windows_vm_id" {
  description = "VM 資源 ID"
  value       = module.windows.vm_id
}

output "vnet_id" {
  description = "VNet ID（供其他環境 VNet Peering 引用）"
  value       = module.vnet.vnet_id
}

output "resource_group_name" {
  description = "Resource Group 名稱"
  value       = module.vnet.resource_group_name
}

output "rdp_command" {
  description = "RDP 連線指令"
  value       = module.windows.rdp_command
}

output "admin_username" {
  description = "RDP 登入帳號"
  value       = module.windows.admin_username
}

output "admin_password" {
  description = "RDP 登入密碼（sensitive）"
  sensitive   = true
  value       = module.windows.admin_password
}

output "connection_guide" {
  description = "連線步驟說明"
  value       = <<-EOT
    ┌─────────────────────────────────────────────────┐
    │  連線步驟                                        │
    ├─────────────────────────────────────────────────┤
    │  1. 取得 RDP 密碼                                │
    │     terraform output -raw admin_password         │
    │                                                 │
    │  2. RDP 連入 Windows VM                         │
    │     ${module.windows.rdp_command}
    │     User: ${module.windows.admin_username}
    │                                                 │
    │  3. 若使用自動生成密碼，密碼檔位於：            │
    │     terraform output -raw password_file_path    │
    └─────────────────────────────────────────────────┘
  EOT
}

output "password_file_path" {
  description = "自動生成密碼的本地路徑（admin_password = null 時才有值）"
  sensitive   = true
  value       = module.windows.password_file_path
}
