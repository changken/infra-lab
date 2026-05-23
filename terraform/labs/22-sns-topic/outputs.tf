output "topic_arn" {
  description = "SNS Topic ARN（用於發布訊息）"
  value       = aws_sns_topic.main.arn
}

output "sqs_queue_url" {
  description = "SQS 訂閱者 Queue URL（用於確認收到訊息）"
  value       = aws_sqs_queue.subscriber.url
}

output "lambda_function_name" {
  description = "Lambda 訂閱者函數名稱"
  value       = aws_lambda_function.handler.function_name
}
