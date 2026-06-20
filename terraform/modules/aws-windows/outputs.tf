# ---------- Outputs ----------
output "instance_id" {
  description = "EC2 Spot instance ID"
  value       = aws_instance.win2025.id
}

output "public_ip" {
  description = "Public IP address of the instance"
  value       = aws_instance.win2025.public_ip
}

output "rdp_password_command" {
  description = "AWS CLI command to retrieve the RDP password"
  sensitive   = true
  value       = var.public_key_content == null ? "aws ec2 get-password-data --instance-id ${aws_instance.win2025.id} --priv-launch-key ${path.module}/${var.name_prefix}-key.pem" : "Private key not managed by Terraform — provide it manually."
}

output "private_key_path" {
  description = "Path to the auto-generated private key file (only set when public_key_content is null)"
  sensitive   = true
  value       = var.public_key_content == null ? "${path.module}/${var.name_prefix}-key.pem" : null
}

output "security_group_id" {
  description = "Windows Spot EC2 的 Security Group ID（供 Aurora allowed_security_groups 引用）"
  value       = aws_security_group.win2025.id
}
