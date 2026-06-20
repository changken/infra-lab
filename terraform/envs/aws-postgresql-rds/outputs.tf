output "endpoint" {
  description = "RDS connection endpoint (host:port)"
  value       = aws_db_instance.postgresql.endpoint
}

output "address" {
  description = "RDS hostname only"
  value       = aws_db_instance.postgresql.address
}

output "port" {
  description = "PostgreSQL port"
  value       = aws_db_instance.postgresql.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.postgresql.db_name
}

output "psql_command" {
  description = "psql 連線指令（填入密碼後執行）"
  value       = format("psql -h %s -p %s -U %s -d %s", aws_db_instance.postgresql.address, aws_db_instance.postgresql.port, var.db_username, aws_db_instance.postgresql.db_name)
}

output "jdbc_url" {
  description = "JDBC connection URL"
  value       = format("jdbc:postgresql://%s:%s/%s", aws_db_instance.postgresql.address, aws_db_instance.postgresql.port, aws_db_instance.postgresql.db_name)
}

output "security_group_id" {
  description = "PostgreSQL RDS Security Group ID"
  value       = aws_security_group.postgresql_rds.id
}
