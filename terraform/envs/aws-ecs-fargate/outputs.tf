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

# ── CloudWatch Dashboard ─────────────────────────────────────

output "dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${local.name_prefix}"
}

# ── Scheduled Task ───────────────────────────────────────────

output "job_task_definition" {
  description = "Job Task Definition family（手動觸發測試用）"
  value       = aws_ecs_task_definition.job.family
}

output "job_run_command" {
  description = "手動觸發一次 job task 的指令"
  value       = <<-EOT
    aws ecs run-task \
      --cluster ${aws_ecs_cluster.main.name} \
      --task-definition ${aws_ecs_task_definition.job.family} \
      --launch-type FARGATE \
      --network-configuration 'awsvpcConfiguration={subnets=[${join(",", [for s in aws_subnet.public : s.id])}],securityGroups=[${aws_security_group.ecs_tasks.id}],assignPublicIp=ENABLED}' \
      --query 'tasks[0].taskArn' --output text
  EOT
}

output "job_logs_command" {
  description = "查看 job 執行日誌"
  value       = "aws logs tail ${aws_cloudwatch_log_group.app.name} --log-stream-name-prefix job --follow"
}

# ── Blue/Green ───────────────────────────────────────────────

output "alb_test_url" {
  description = "Test Listener（:8080）→ Green TG，部署期間預覽新版本用"
  value       = "http://${aws_lb.main.dns_name}:8080"
}

output "codedeploy_app_name" {
  description = "CodeDeploy Application 名稱"
  value       = aws_codedeploy_app.app.name
}

output "codedeploy_deployment_group" {
  description = "CodeDeploy Deployment Group 名稱"
  value       = aws_codedeploy_deployment_group.app.deployment_group_name
}

output "blue_target_group_name" {
  description = "Blue Target Group 名稱（CodeDeploy appspec 用）"
  value       = aws_lb_target_group.blue.name
}

output "green_target_group_name" {
  description = "Green Target Group 名稱（CodeDeploy appspec 用）"
  value       = aws_lb_target_group.green.name
}

output "deploy_command" {
  description = "觸發 Blue/Green 部署的 CLI 指令範例"
  value       = <<-EOT
    # 1. 取得最新 task definition ARN
    TASK_DEF_ARN=$(aws ecs describe-task-definition \
      --task-definition ${aws_ecs_cluster.main.name} \
      --query 'taskDefinition.taskDefinitionArn' --output text)

    # 2. 觸發 CodeDeploy deployment
    aws deploy create-deployment \
      --application-name ${aws_codedeploy_app.app.name} \
      --deployment-group-name ${aws_codedeploy_deployment_group.app.deployment_group_name} \
      --revision '{"revisionType":"AppSpecContent","appSpecContent":{"content":"{\"version\":0.0,\"Resources\":[{\"TargetService\":{\"Type\":\"AWS::ECS::Service\",\"Properties\":{\"TaskDefinition\":\"'$TASK_DEF_ARN'\",\"LoadBalancerInfo\":{\"ContainerName\":\"app\",\"ContainerPort\":${var.container_port}}}}}]}"}}'
  EOT
}
