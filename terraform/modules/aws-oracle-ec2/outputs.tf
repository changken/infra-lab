output "public_ip" {
  description = "EC2 public IP"
  value       = aws_instance.oracle.public_ip
}

output "jdbc_url" {
  description = "JDBC Thin connection URL (PDB)"
  value       = "jdbc:oracle:thin:@//${aws_instance.oracle.public_ip}:1521/XEPDB1"
}

output "sqlplus_command" {
  description = "SQL*Plus connection command"
  value       = "sqlplus system/${var.oracle_password}@//${aws_instance.oracle.public_ip}:1521/XEPDB1"
  sensitive   = true
}

output "em_express_url" {
  description = "Oracle EM Express Web UI"
  value       = "https://${aws_instance.oracle.public_ip}:5500/em"
}

output "docker_logs_command" {
  description = "查看 Oracle 初始化進度"
  value       = "ssh ec2-user@${aws_instance.oracle.public_ip} 'sudo docker logs -f oracle-xe'"
}
