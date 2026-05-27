output "ecr_repo_url" {
  description = "ECR Repository URL（填入 GitHub Secrets: ECR_REPOSITORY）"
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "GitHub Actions IAM Role ARN（填入 GitHub Secrets: AWS_ROLE_ARN）"
  value       = aws_iam_role.github_actions.arn
}

output "artifact_bucket_name" {
  description = "S3 Artifact Bucket 名稱（填入 GitHub Secrets: ARTIFACT_BUCKET）"
  value       = aws_s3_bucket.artifacts.id
}

output "alb_prod_url" {
  description = "ALB 生產流量入口（Port 80）"
  value       = "http://${aws_lb.main.dns_name}"
}

output "alb_test_url" {
  description = "ALB 測試流量入口（Port 8080，Blue/Green 部署期間驗證新版本用）"
  value       = "http://${aws_lb.main.dns_name}:8080"
}

output "ecs_execution_role_arn" {
  description = "ECS Task Execution Role ARN（填入 deploy/taskdef.json 的 executionRoleArn）"
  value       = aws_iam_role.ecs_execution.arn
}

output "pipeline_name" {
  description = "CodePipeline 名稱（用於監控部署進度）"
  value       = aws_codepipeline.main.name
}

output "pipeline_status_command" {
  description = "查詢最近一次 Pipeline 執行狀態的 CLI 指令"
  value       = "aws codepipeline get-pipeline-state --name ${aws_codepipeline.main.name} --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' --output table"
}

output "github_secrets_summary" {
  description = "需要在 GitHub Secrets 設定的值（apply 後複製）"
  value       = <<-EOT
    AWS_ROLE_ARN      = ${aws_iam_role.github_actions.arn}
    ECR_REPOSITORY    = ${aws_ecr_repository.app.name}
    ARTIFACT_BUCKET   = ${aws_s3_bucket.artifacts.id}
    AWS_REGION        = ${var.region}
  EOT
}
