#--------------------------------------------------------------
# EC2 Instance Outputs
#--------------------------------------------------------------

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.my_instance.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.my_instance.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.my_instance.public_dns
}

#--------------------------------------------------------------
# SSH Key Outputs
#--------------------------------------------------------------

output "private_key_path" {
  description = "Path to the private key file"
  value       = local_file.private_key.filename
}

output "ssh_connection_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${local_file.private_key.filename} ec2-user@${aws_instance.my_instance.public_ip}"
}

#--------------------------------------------------------------
# Security Group Outputs
#--------------------------------------------------------------

output "security_group_id" {
  description = "ID of the web security group"
  value       = aws_security_group.web_sg.id
}
