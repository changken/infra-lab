output "state_machine_arn" {
  description = "Step Functions State Machine ARN"
  value       = aws_sfn_state_machine.order_workflow.arn
}

output "state_machine_name" {
  description = "Step Functions State Machine 名稱"
  value       = aws_sfn_state_machine.order_workflow.name
}

output "sns_topic_arn" {
  description = "SNS Topic ARN（訂單通知）"
  value       = aws_sns_topic.orders.arn
}

output "start_execution_success" {
  description = "啟動工作流程（成功案例）"
  value       = <<-EOT
    aws stepfunctions start-execution \
      --state-machine-arn ${aws_sfn_state_machine.order_workflow.arn} \
      --name "test-success-$(date +%s)" \
      --input '{
        "order_id": "ORD-001",
        "customer_email": "customer@example.com",
        "items": [{"sku": "SKU-A", "quantity": 2, "price": 29.99}],
        "total_amount": 59.98
      }'
  EOT
}

output "start_execution_oos" {
  description = "啟動工作流程（庫存不足 → ReserveInventory 失敗）"
  value       = <<-EOT
    aws stepfunctions start-execution \
      --state-machine-arn ${aws_sfn_state_machine.order_workflow.arn} \
      --name "test-oos-$(date +%s)" \
      --input '{
        "order_id": "ORD-002",
        "customer_email": "customer@example.com",
        "items": [{"sku": "SKU-OOS", "quantity": 1, "price": 9.99}],
        "total_amount": 9.99
      }'
  EOT
}

output "start_execution_invalid" {
  description = "啟動工作流程（驗證失敗 → ValidateOrder 失敗）"
  value       = <<-EOT
    aws stepfunctions start-execution \
      --state-machine-arn ${aws_sfn_state_machine.order_workflow.arn} \
      --name "test-invalid-$(date +%s)" \
      --input '{"order_id": "ORD-003"}'
  EOT
}

output "list_executions" {
  description = "列出最近的執行記錄"
  value       = "aws stepfunctions list-executions --state-machine-arn ${aws_sfn_state_machine.order_workflow.arn} --max-results 10"
}

output "console_url" {
  description = "Step Functions Console URL"
  value       = "https://${var.region}.console.aws.amazon.com/states/home?region=${var.region}#/statemachines"
}
