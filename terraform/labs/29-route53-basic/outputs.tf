output "zone_id" {
  description = "Private Hosted Zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "zone_name" {
  description = "Private Hosted Zone 域名"
  value       = aws_route53_zone.private.name
}

output "app_fqdn" {
  description = "app A Record 完整域名"
  value       = aws_route53_record.app.fqdn
}

output "api_fqdn" {
  description = "api CNAME Record 完整域名"
  value       = aws_route53_record.api.fqdn
}

output "health_check_id" {
  description = "Health Check ID"
  value       = aws_route53_health_check.main.id
}
