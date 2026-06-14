output "lambda_function_name" {
  description = "Guard Lambda function name"
  value       = aws_lambda_function.guard.function_name
}

output "lambda_arn" {
  description = "Guard Lambda ARN"
  value       = aws_lambda_function.guard.arn
}

output "sns_topic_arn" {
  description = "Billing alert SNS topic ARN"
  value       = aws_sns_topic.billing_alert.arn
}

output "budget_name" {
  description = "AWS Budget name"
  value       = aws_budgets_budget.monthly.name
}
