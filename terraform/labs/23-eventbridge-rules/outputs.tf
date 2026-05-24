output "custom_bus_name" {
  description = "Custom Event Bus 名稱（put-events 時指定 --event-bus-name）"
  value       = aws_cloudwatch_event_bus.custom.name
}

output "scheduler_function_name" {
  description = "排程 Lambda 函數名稱"
  value       = aws_lambda_function.scheduler.function_name
}

output "processor_function_name" {
  description = "事件處理 Lambda 函數名稱"
  value       = aws_lambda_function.processor.function_name
}
