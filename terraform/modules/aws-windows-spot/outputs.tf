# ---------- Outputs ----------
output "instance_id" {
  value = aws_instance.win2025.id
}

output "public_ip" {
  value = aws_instance.win2025.public_ip
}

output "rdp_password_command" {
  value = "aws ec2 get-password-data --instance-id ${aws_instance.win2025.id} --priv-launch-key ${local_file.private_key.filename}"
}

output "private_key_path" {
  value = local_file.private_key.filename
}
