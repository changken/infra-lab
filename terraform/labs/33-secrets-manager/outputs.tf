output "secret_arn" {
  description = "Secrets Manager Secret ARN"
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Secrets Manager Secret 名稱"
  value       = aws_secretsmanager_secret.db.name
}

output "kms_key_id" {
  description = "KMS Key ID"
  value       = aws_kms_key.main.key_id
}

output "kms_key_arn" {
  description = "KMS Key ARN"
  value       = aws_kms_key.main.arn
}

output "rotation_lambda_name" {
  description = "Rotation Lambda 函數名稱"
  value       = aws_lambda_function.rotation.function_name
}

output "secrets_console_url" {
  description = "Secrets Manager Console 連結"
  value       = "https://${var.region}.console.aws.amazon.com/secretsmanager/listsecrets"
}
