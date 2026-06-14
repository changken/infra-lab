output "sns_topic_arn" {
  value = aws_sns_topic.rds_schedule.arn
}

output "stop_lambda_name" {
  value = aws_lambda_function.stop.function_name
}

output "start_lambda_name" {
  value = aws_lambda_function.start.function_name
}
