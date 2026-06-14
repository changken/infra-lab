output "endpoint" {
  description = "RDS connection endpoint (host:port)"
  value       = aws_db_instance.oracle.endpoint
}

output "address" {
  description = "RDS hostname only"
  value       = aws_db_instance.oracle.address
}

output "port" {
  description = "Oracle listener port"
  value       = aws_db_instance.oracle.port
}

output "db_name" {
  description = "Oracle SID"
  value       = aws_db_instance.oracle.db_name
}

output "jdbc_url" {
  description = "JDBC Thin connection URL"
  value       = format("jdbc:oracle:thin:@//%s:%s/%s", aws_db_instance.oracle.address, aws_db_instance.oracle.port, aws_db_instance.oracle.db_name)
}

output "sqlplus_command" {
  description = "SQL*Plus connection command (fill in password)"
  value       = format("sqlplus %s@//%s:%s/%s", var.db_username, aws_db_instance.oracle.address, aws_db_instance.oracle.port, aws_db_instance.oracle.db_name)
}

output "security_group_id" {
  description = "Oracle RDS Security Group ID"
  value       = aws_security_group.oracle_rds.id
}
