output "topic_arn" {
  description = "SNS Topic ARN（發布訂單事件用）"
  value       = aws_sns_topic.orders.arn
}

output "inventory_queue_url" {
  description = "庫存 SQS Queue URL"
  value       = aws_sqs_queue.inventory.url
}

output "notification_queue_url" {
  description = "通知 SQS Queue URL"
  value       = aws_sqs_queue.notification.url
}

output "inventory_dlq_url" {
  description = "庫存 DLQ URL（觀察失敗訊息）"
  value       = aws_sqs_queue.inventory_dlq.url
}

output "notification_dlq_url" {
  description = "通知 DLQ URL（觀察失敗訊息）"
  value       = aws_sqs_queue.notification_dlq.url
}
