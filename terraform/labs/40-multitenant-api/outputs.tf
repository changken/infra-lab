output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  description = "Cognito App Client ID（initiate-auth 用）"
  value       = aws_cognito_user_pool_client.main.id
}

output "api_endpoint" {
  description = "API Gateway Endpoint（$default Stage，無 /stage 前綴）"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "dynamodb_table_name" {
  description = "DynamoDB Table 名稱"
  value       = aws_dynamodb_table.items.id
}

output "create_tenant_a_user" {
  description = "建立 Tenant A 測試用戶的 CLI 指令"
  value       = <<-EOT
    aws cognito-idp admin-create-user \
      --user-pool-id ${aws_cognito_user_pool.main.id} \
      --username user-a@example.com \
      --user-attributes \
        Name=email,Value=user-a@example.com \
        Name=custom:tenant_id,Value=tenant-A \
      --temporary-password TempPass123! \
      --message-action SUPPRESS
  EOT
}

output "set_permanent_password" {
  description = "設定永久密碼（跳過 NEW_PASSWORD_REQUIRED 挑戰）"
  value       = <<-EOT
    aws cognito-idp admin-set-user-password \
      --user-pool-id ${aws_cognito_user_pool.main.id} \
      --username user-a@example.com \
      --password MyPassword123! \
      --permanent
  EOT
}

output "get_token_command" {
  description = "取得 JWT IdToken（替換 USERNAME 和 PASSWORD）"
  value       = <<-EOT
    aws cognito-idp initiate-auth \
      --auth-flow USER_PASSWORD_AUTH \
      --client-id ${aws_cognito_user_pool_client.main.id} \
      --auth-parameters USERNAME=user-a@example.com,PASSWORD=MyPassword123! \
      --query 'AuthenticationResult.IdToken' \
      --output text
  EOT
}

output "curl_post_item" {
  description = "新增 Item（替換 TOKEN）"
  value       = "curl -s -X POST -H 'Authorization: Bearer <TOKEN>' -H 'Content-Type: application/json' -d '{\"name\":\"my-item\",\"data\":{\"key\":\"value\"}}' ${aws_apigatewayv2_stage.default.invoke_url}/items"
}

output "curl_get_items" {
  description = "列出此租戶的 Items（替換 TOKEN）"
  value       = "curl -s -H 'Authorization: Bearer <TOKEN>' ${aws_apigatewayv2_stage.default.invoke_url}/items"
}

output "dynamodb_query_tenant" {
  description = "直接查詢 DynamoDB 確認租戶隔離（替換 TENANT_ID）"
  value       = "aws dynamodb query --table-name ${aws_dynamodb_table.items.id} --key-condition-expression 'pk = :pk' --expression-attribute-values '{\":pk\":{\"S\":\"TENANT#<TENANT_ID>\"}}'"
}
