output "api_endpoint" {
  description = "API Gateway 端點（POST /hello）"
  value       = "${aws_api_gateway_stage.dev.invoke_url}/hello"
}

output "api_stage_arn" {
  description = "API Gateway Stage ARN"
  value       = aws_api_gateway_stage.dev.arn
}

output "lambda_function_name" {
  description = "Lambda 函數名稱"
  value       = aws_lambda_function.handler.function_name
}

output "xray_console_url" {
  description = "X-Ray Console 連結（需登入 AWS Console）"
  value       = "https://${var.region}.console.aws.amazon.com/xray/home#/traces"
}
