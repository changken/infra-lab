output "alb_dns_name" {
  description = "ALB DNS，貼到瀏覽器驗證服務 http://<dns>/health"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR image URI，docker push 用"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster 名稱"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service 名稱（更新用）"
  value       = aws_ecs_service.app.name
}

output "github_actions_role_arn" {
  description = "GitHub Actions Role ARN → 填入 GitHub Secret: AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "task_execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ECS Task Role ARN（容器呼叫 AWS API 用）"
  value       = aws_iam_role.task.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group，查看容器日誌用"
  value       = aws_cloudwatch_log_group.app.name
}

output "secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.app_config.arn
}

output "exec_command" {
  description = "ECS Exec 進入容器（類似 kubectl exec）"
  value       = "aws ecs execute-command --cluster ${aws_ecs_cluster.main.name} --task <TASK_ID> --container app --interactive --command /bin/sh"
}
