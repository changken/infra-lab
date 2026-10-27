output "linux_public_ip" {
  description = "Linux VM 公網 IP"
  value       = module.linux.public_ip
}

output "linux_private_ip" {
  description = "Linux VM 私有 IP"
  value       = module.linux.private_ip
}

output "linux_vm_id" {
  description = "VM 資源 ID"
  value       = module.linux.vm_id
}

output "vnet_id" {
  description = "VNet ID（供其他環境 VNet Peering 引用）"
  value       = module.vnet.vnet_id
}

output "resource_group_name" {
  description = "Resource Group 名稱"
  value       = module.vnet.resource_group_name
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = module.linux.ssh_command
  sensitive   = true
}

output "connection_guide" {
  description = "連線步驟說明"
  value       = <<-EOT
    ┌─────────────────────────────────────────────────┐
    │  連線步驟                                        │
    ├─────────────────────────────────────────────────┤
    │  1. 取得 SSH 連線指令                            │
    │     terraform output ssh_command                 │
    │                                                 │
    │  2. SSH 連入 Linux VM                           │
    │     ${module.linux.ssh_command}
    │                                                 │
    │  3. 若使用自動生成金鑰，私鑰位於：              │
    │     terraform output -raw private_key_path      │
    └─────────────────────────────────────────────────┘
  EOT
  sensitive   = true
}

output "private_key_path" {
  description = "自動生成金鑰的本地路徑（admin_ssh_public_key = null 時才有值）"
  sensitive   = true
  value       = module.linux.private_key_path
}
