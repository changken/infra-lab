output "windows_public_ip" {
  description = "Windows Bastion 公網 IP（用 RDP 連入）"
  value       = module.windows.public_ip
}

output "windows_instance_id" {
  description = "EC2 Instance ID"
  value       = module.windows.instance_id
}

output "windows_security_group_id" {
  description = "Security Group ID（可供其他環境的 allowed_security_groups 引用）"
  value       = module.windows.security_group_id
}

output "rdp_password_command" {
  description = "取得 RDP 密碼的 AWS CLI 指令"
  sensitive   = true
  value       = module.windows.rdp_password_command
}

output "connection_guide" {
  description = "連線步驟說明"
  value       = <<-EOT
    ┌─────────────────────────────────────────────────┐
    │  連線步驟                                        │
    ├─────────────────────────────────────────────────┤
    │  1. 取得 RDP 密碼                                │
    │     terraform output -raw rdp_password_command  │
    │     執行輸出的 aws ec2 get-password-data 指令    │
    │                                                 │
    │  2. RDP 連入 Windows Bastion                    │
    │     IP:   ${module.windows.public_ip}
    │     Port: 3389                                  │
    │     User: Administrator                         │
    │                                                 │
    │  3. 或使用 SSM Session Manager（免 RDP port）   │
    │     aws ssm start-session \                     │
    │       --target ${module.windows.instance_id}
    └─────────────────────────────────────────────────┘
  EOT
}
