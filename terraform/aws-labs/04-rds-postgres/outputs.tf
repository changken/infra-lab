output "rds_endpoint" {
  description = "RDS connection endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS hostname only"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

# TODO: psql_command
#   提示：用 format() 組出 psql 連線指令：
#   "psql -h %s -p %s -U %s -d %s"
#   引數依序：address, port, username, db_name
#   （password 不放在這裡）

output "psql_command" {
  description = "psql connection command"
  value       = format("psql -h %s -p %s -U %s -d %s",
    aws_db_instance.main.address,
    aws_db_instance.main.port,
    var.db_username,
    aws_db_instance.main.db_name)
}