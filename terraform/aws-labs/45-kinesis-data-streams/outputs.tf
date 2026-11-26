output "api_endpoint" {
  description = "Producer API Gateway endpoint"
  value       = aws_apigatewayv2_stage.producer.invoke_url
}

output "stream_name" {
  description = "Kinesis Data Stream 名稱"
  value       = aws_kinesis_stream.events.name
}

output "stream_arn" {
  description = "Kinesis Data Stream ARN"
  value       = aws_kinesis_stream.events.arn
}

output "dynamodb_table" {
  description = "DynamoDB 聚合計數表名稱"
  value       = aws_dynamodb_table.aggregation.name
}

output "send_events_command" {
  description = "發送一批隨機事件到 Kinesis"
  value       = "curl -s -X POST ${aws_apigatewayv2_stage.producer.invoke_url}/events -H 'Content-Type: application/json' -d '{\"count\": 50}' | jq ."
}

output "send_single_event" {
  description = "發送單筆自訂事件"
  value       = "curl -s -X POST ${aws_apigatewayv2_stage.producer.invoke_url}/events -H 'Content-Type: application/json' -d '{\"event_type\": \"purchase\", \"user_id\": \"user-99\", \"amount\": 199.9}' | jq ."
}

output "scan_aggregation_table" {
  description = "掃描 DynamoDB 聚合結果"
  value       = "aws dynamodb scan --table-name ${aws_dynamodb_table.aggregation.name} --query 'Items[*].{type: event_type.S, count: count.N}' --output table"
}

output "get_stream_metrics" {
  description = "查看 Kinesis Stream 指標（最近 5 分鐘的 IteratorAge）"
  value       = <<-EOT
    aws cloudwatch get-metric-statistics \
      --namespace AWS/Kinesis \
      --metric-name GetRecords.IteratorAgeMilliseconds \
      --dimensions Name=StreamName,Value=${aws_kinesis_stream.events.name} \
      --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
      --period 60 \
      --statistics Maximum \
      --output table
  EOT
}

output "describe_stream" {
  description = "查看 Kinesis Stream 詳細資訊（Shard 狀態）"
  value       = "aws kinesis describe-stream-summary --stream-name ${aws_kinesis_stream.events.name}"
}

output "consumer_function_name" {
  description = "Consumer Lambda 函數名稱"
  value       = aws_lambda_function.consumer.function_name
}
