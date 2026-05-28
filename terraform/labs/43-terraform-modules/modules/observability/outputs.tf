output "sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  value       = aws_sns_topic.alarms.arn
}

output "lambda_errors_alarm_name" {
  description = "CloudWatch alarm name for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}
