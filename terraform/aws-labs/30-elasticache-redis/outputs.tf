output "redis_endpoint" {
  description = "ElastiCache Redis 端點（僅 VPC 內可連線）"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_cluster.redis.port
}

output "lambda_function_name" {
  description = "測試 Lambda 函數名稱"
  value       = aws_lambda_function.redis_test.function_name
}
