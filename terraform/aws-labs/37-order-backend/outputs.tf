output "api_endpoint" {
  description = "API Gateway 入口 URL（POST /orders）"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/orders"
}

output "orders_table_name" {
  description = "DynamoDB 訂單資料表名稱"
  value       = aws_dynamodb_table.orders.name
}

output "orders_queue_url" {
  description = "SQS 訂單佇列 URL"
  value       = aws_sqs_queue.orders.url
}

output "dlq_url" {
  description = "DLQ URL（監控失敗訂單）"
  value       = aws_sqs_queue.orders_dlq.url
}

output "sns_topic_arn" {
  description = "SNS Topic ARN（訂單通知）"
  value       = aws_sns_topic.orders.arn
}

output "curl_example" {
  description = "測試用 curl 指令（建立訂單）"
  value       = <<-EOT
    curl -s -X POST "${aws_apigatewayv2_stage.default.invoke_url}/orders" \
      -H "Content-Type: application/json" \
      -d '{"customer_id":"cust-001","items":[{"sku":"ITEM-A","qty":2}],"total_amount":59.90}'
  EOT
}

output "dynamodb_scan_command" {
  description = "掃描 DynamoDB 查詢所有訂單的 CLI 指令"
  value       = "aws dynamodb scan --table-name ${aws_dynamodb_table.orders.name} --query 'Items[*].{ID:order_id.S,Customer:customer_id.S,Status:status.S}' --output table"
}

output "dlq_message_count_command" {
  description = "查詢 DLQ 訊息數量的 CLI 指令（用於監控失敗訂單）"
  value       = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.orders_dlq.url} --attribute-names ApproximateNumberOfMessages"
}
