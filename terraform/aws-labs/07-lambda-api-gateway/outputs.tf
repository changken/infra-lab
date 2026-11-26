output "api_endpoint" {
  description = "API Gateway base URL"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "hello_url" {
  description = "Full URL to call the hello endpoint"
  value       = "${aws_apigatewayv2_api.main.api_endpoint}/hello"
}

# TODO: curl_command
#   提示：用 format() 組出 curl 指令：
#   "curl '%s/hello?name=Terraform'"
#   引數：aws_apigatewayv2_api.main.api_endpoint

output "curl_command" {
  description = "Example curl command to call the API"
  value = format("curl '%s/hello?name=Terraform'", aws_apigatewayv2_api.main.api_endpoint)
}