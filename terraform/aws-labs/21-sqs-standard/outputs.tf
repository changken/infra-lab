output "queue_url" {
  description = "Main SQS Queue URL（用於發送訊息）"
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "Main SQS Queue ARN"
  value       = aws_sqs_queue.main.arn
}

output "dlq_url" {
  description = "Dead Letter Queue URL（用於查看失敗訊息）"
  value       = aws_sqs_queue.dlq.url
}

# TODO: 補上 lambda_function_name output
# value = aws_lambda_function.consumer.function_name
output "lambda_function_name" {
  description = "Lambda Consumer 函數名稱"
  value       = aws_lambda_function.consumer.function_name
}
