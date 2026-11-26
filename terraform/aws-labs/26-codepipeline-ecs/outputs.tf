output "pipeline_name" {
  description = "CodePipeline 名稱"
  value       = aws_codepipeline.main.name
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS Cluster 名稱"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS Service 名稱"
  value       = aws_ecs_service.app.name
}

output "source_bucket" {
  description = "S3 Source Bucket（更新 source.zip 觸發 Pipeline）"
  value       = aws_s3_bucket.source.id
}
