#==============================================================
# Lab 48 - Outputs
#==============================================================

output "windows_public_ip" {
  description = "Windows Bastion 公網 IP（用 RDP 連入）"
  value       = module.windows.public_ip
}

output "windows_rdp_password_command" {
  description = "取得 RDP 密碼的 AWS CLI 指令"
  sensitive   = true
  value       = module.windows.rdp_password_command
}

output "aurora_endpoint" {
  description = "Aurora Writer Endpoint（在 Windows 上用此位址連 PostgreSQL）"
  value       = module.aurora.cluster_endpoint
}

output "aurora_port" {
  description = "PostgreSQL 連線 Port"
  value       = module.aurora.port
}

output "aurora_db_name" {
  description = "預設資料庫名稱"
  value       = module.aurora.db_name
}

output "connection_guide" {
  description = "連線步驟說明"
  value       = <<-EOT
    ┌─────────────────────────────────────────────────┐
    │  連線步驟                                        │
    ├─────────────────────────────────────────────────┤
    │  1. RDP 連入 Windows Bastion                    │
    │     IP:   ${module.windows.public_ip}
    │     Port: 3389                                  │
    │                                                 │
    │  2. 在 Windows 上安裝 DBeaver / pgAdmin         │
    │                                                 │
    │  3. 以下列參數連接 Aurora                        │
    │     Host: ${module.aurora.cluster_endpoint}
    │     Port: ${module.aurora.port}                              │
    │     DB:   ${module.aurora.db_name}                             │
    └─────────────────────────────────────────────────┘
  EOT
}
