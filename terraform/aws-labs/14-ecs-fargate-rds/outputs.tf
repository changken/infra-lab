output "alb_url" {
  description = "Flask app URL（透過 ALB）"
  value       = "http://${aws_lb.main.dns_name}"
}

output "rds_endpoint" {
  description = "RDS endpoint（host:port，Task Definition 的 DB_HOST 就是這個）"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_address" {
  description = "RDS hostname（不含 port）"
  value       = aws_db_instance.postgres.address
}
