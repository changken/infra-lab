output "lambda_function_name" {
  description = "Lambda function name to invoke for testing"
  value       = aws_lambda_function.app.function_name
}

output "sns_topic_arn" {
  description = "SNS Topic ARN for alarm notifications"
  value       = aws_sns_topic.alerts.arn
}

output "alarm_arn" {
  description = "CloudWatch Alarm ARN"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}

output "dashboard_url" {
  description = "CloudWatch Dashboard URL (open in browser)"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.project}"
}

output "invoke_command" {
  description = "Run this repeatedly to generate Lambda invocations (30% will error)"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.app.function_name} --region ${var.region} /dev/null"
}
