output "service_url" {
  description = "ECS Express Gateway 服務的公開 HTTPS URL（由 ALB 自動配發）"
  value       = "https://${aws_ecs_express_gateway_service.app.ingress_paths[0].endpoint}"
}

output "service_arn" {
  description = "Express Gateway Service ARN"
  value       = aws_ecs_express_gateway_service.app.service_arn
}

output "service_revision_arn" {
  description = "目前的 Service Revision ARN（每次更新都會產生新的 Revision）"
  value       = aws_ecs_express_gateway_service.app.service_revision_arn
}
