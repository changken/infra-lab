output "linux_public_ip" {
  description = "Linux Bastion 公網 IP"
  value       = module.linux.public_ip
}

output "linux_instance_id" {
  description = "EC2 Instance ID"
  value       = module.linux.instance_id
}

output "linux_security_group_id" {
  description = "Security Group ID（可供其他環境的 allowed_security_groups 引用）"
  value       = module.linux.security_group_id
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = module.linux.ssh_command
}

output "connection_guide" {
  description = "連線步驟說明"
  value       = <<-EOT
    ┌─────────────────────────────────────────────────┐
    │  連線步驟                                        │
    ├─────────────────────────────────────────────────┤
    │  1. 取得金鑰（自動生成時已存在 module 目錄下）    │
    │                                                 │
    │  2. SSH 連入 Linux Bastion                      │
    │     ${module.linux.ssh_command}
    │                                                 │
    │  3. 或使用 SSM Session Manager（免 Key Pair）    │
    │     aws ssm start-session \                     │
    │       --target ${module.linux.instance_id}
    └─────────────────────────────────────────────────┘
  EOT
}
