output "alb_dns_name" {
  description = "ALB DNS 名稱（固定，不因 Task 重啟改變）"
  value       = "http://${aws_lb.main.dns_name}"
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "target_group_arn" {
  description = "Target Group ARN（可在 Console 查看健康狀態）"
  value       = aws_lb_target_group.app.arn
}
