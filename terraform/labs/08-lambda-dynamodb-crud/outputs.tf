output "api_endpoint" {
  description = "API Gateway base URL"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "items_url" {
  description = "URL for the /items endpoint"
  value       = "${aws_apigatewayv2_api.main.api_endpoint}/items"
}

# TODO: test_commands
#   提示：用 format() 組出多行測試指令字串，一次印出所有 curl 範例：
#   "POST: curl -X POST %s/items -H 'Content-Type: application/json' -d '{\"name\":\"book\"}'\nGET:  curl %s/items"
#   引數（兩個）：api_endpoint, api_endpoint

output "test_commands" {
  description = "Example curl commands to test the API"
  value = format(
    "POST: curl -X POST %s/items -H 'Content-Type: application/json' -d '{\"name\":\"book\"}'\nGET:  curl %s/items",
    aws_apigatewayv2_api.main.api_endpoint,
    aws_apigatewayv2_api.main.api_endpoint
  )
}