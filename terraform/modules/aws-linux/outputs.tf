# ---------- Outputs ----------
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.linux.id
}

output "public_ip" {
  description = "Public IP address of the instance"
  value       = aws_instance.linux.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${path.module}/${var.name_prefix}-key.pem ec2-user@${aws_instance.linux.public_ip}"
}

output "private_key_path" {
  description = "Path to the auto-generated private key file (only set when public_key_content is null)"
  sensitive   = true
  value       = local.use_generated_key ? "${path.module}/${var.name_prefix}-key.pem" : null
}

output "security_group_id" {
  description = "Linux EC2 的 Security Group ID（供其他模組的 allowed_security_groups 引用）"
  value       = aws_security_group.linux.id
}
