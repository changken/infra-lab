output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}

output "app_client_id" {
  description = "Cognito App Client ID（initiate-auth 的 --client-id 參數）"
  value       = aws_cognito_user_pool_client.app.id
}

output "user_pool_domain" {
  description = "Cognito Hosted UI domain prefix"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "user_pool_endpoint" {
  description = "User Pool OIDC Endpoint（JWKS 驗證基礎 URL）"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "jwks_uri" {
  description = "JWT 公鑰端點（API 服務驗證 token 簽名時使用）"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
}
