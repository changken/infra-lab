output "codebuild_project_name" {
  description = "CodeBuild Project 名稱（觸發建置用）"
  value       = aws_codebuild_project.main.name
}

output "ecr_repository_url" {
  description = "ECR Repository URL（image push 目標）"
  value       = aws_ecr_repository.app.repository_url
}

output "source_bucket" {
  description = "S3 Source Bucket 名稱"
  value       = aws_s3_bucket.source.id
}

output "log_group" {
  description = "CloudWatch Log Group 名稱"
  value       = aws_cloudwatch_log_group.codebuild.name
}
