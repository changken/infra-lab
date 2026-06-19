#==============================================================
# AWS Aurora PostgreSQL Module - Output Values
#==============================================================

output "cluster_endpoint" {
  description = "Aurora Cluster 寫入點 (Writer Endpoint)"
  value       = aws_rds_cluster.aurora.endpoint
}

output "reader_endpoint" {
  description = "Aurora Cluster 唯讀點 (Reader Endpoint)"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "port" {
  description = "資料庫連線 Port"
  value       = aws_rds_cluster.aurora.port
}

output "db_name" {
  description = "預設建立的資料庫名稱"
  value       = aws_rds_cluster.aurora.database_name
}

output "cluster_security_group_id" {
  description = "資料庫 Security Group ID"
  value       = aws_security_group.aurora.id
}
