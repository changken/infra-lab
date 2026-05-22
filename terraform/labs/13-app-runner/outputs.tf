output "service_url" {
  description = "App Runner 服務的 HTTPS URL（自動配發，不需要另外設定憑證）"
  value       = "https://${aws_apprunner_service.app.service_url}"
}

output "service_arn" {
  description = "App Runner service ARN"
  value       = aws_apprunner_service.app.arn
}

output "service_id" {
  description = "App Runner service ID（用於 aws cli 查詢）"
  value       = aws_apprunner_service.app.service_id
}
