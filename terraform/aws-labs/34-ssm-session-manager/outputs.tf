output "instance_id" {
  description = "EC2 Instance ID（用於 SSM Session Manager 連線）"
  value       = aws_instance.ssm_target.id
}

output "instance_public_ip" {
  description = "EC2 Public IP（用於確認 Public Subnet 路由正確；不用於 SSH）"
  value       = aws_instance.ssm_target.public_ip
}

output "patch_baseline_id" {
  description = "SSM Patch Baseline ID"
  value       = aws_ssm_patch_baseline.amazon_linux_2023.id
}

output "maintenance_window_id" {
  description = "SSM Maintenance Window ID"
  value       = aws_ssm_maintenance_window.weekly.id
}

output "ssm_start_session_command" {
  description = "啟動 Session Manager 互動式 Shell 的指令（需安裝 AWS CLI + session-manager-plugin）"
  value       = "aws ssm start-session --target ${aws_instance.ssm_target.id} --region ${var.region}"
}

output "ssm_console_url" {
  description = "SSM Fleet Manager Console 連結（查看 EC2 SSM 狀態）"
  value       = "https://${var.region}.console.aws.amazon.com/systems-manager/managed-instances/${aws_instance.ssm_target.id}/general"
}
