output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.hello.function_name
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.hello.arn
}

# TODO: invoke_command
#   提示：用 format() 組出 AWS CLI 呼叫指令：
#   "aws lambda invoke --function-name %s --payload '%s' /tmp/response.json"
#   引數：function_name, jsonencode({ name = "Terraform" })
#   （這樣 apply 完你就知道怎麼測試了）

output "invoke_command"{
  description = "AWS CLI command to invoke the Lambda function"
  value       = format("aws lambda invoke --function-name %s --payload '%s' /tmp/response.json",
    aws_lambda_function.hello.function_name,
    jsonencode({ name = "Terraform" }))
}