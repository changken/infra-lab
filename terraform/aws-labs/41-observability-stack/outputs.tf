output "api_endpoint" {
  description = "API Gateway Endpoint"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "dashboard_url" {
  description = "CloudWatch Dashboard 直連 URL"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "xray_traces_url" {
  description = "X-Ray Traces 直連 URL"
  value       = "https://${var.region}.console.aws.amazon.com/xray/home?region=${var.region}#/traces"
}

output "canary_console_url" {
  description = "Synthetics Canary 監控頁面"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#synthetics:canary/detail/${aws_synthetics_canary.api_heartbeat.name}"
}

output "sns_topic_arn" {
  description = "SNS Topic ARN（Alarm 通知目標）"
  value       = aws_sns_topic.alarms.arn
}

output "load_test_normal" {
  description = "壓測正常路徑（for X-Ray + Dashboard 觀察）"
  value       = "for i in $(seq 1 20); do curl -s ${aws_apigatewayv2_stage.default.invoke_url}/ > /dev/null; done"
}

output "load_test_slow" {
  description = "壓測慢路徑（for Duration P99 觀察）"
  value       = "for i in $(seq 1 5); do curl -s ${aws_apigatewayv2_stage.default.invoke_url}/slow > /dev/null; done"
}

output "load_test_error" {
  description = "壓測錯誤路徑（for Lambda Errors Alarm 觸發）"
  value       = "for i in $(seq 1 10); do curl -s ${aws_apigatewayv2_stage.default.invoke_url}/error > /dev/null; done"
}

output "load_test_random" {
  description = "壓測隨機錯誤路徑（for Error Rate 觀察）"
  value       = "for i in $(seq 1 30); do curl -s ${aws_apigatewayv2_stage.default.invoke_url}/random > /dev/null; done"
}

output "logs_insights_query" {
  description = "CloudWatch Logs Insights 查詢範例（按路徑統計請求數）"
  value       = <<-EOT
    # 在 CloudWatch Logs Insights 貼入：
    fields @timestamp, path, event, error
    | filter ispresent(path)
    | stats count() as requests, count(error) as errors by path
    | sort requests desc
  EOT
}
