output "role_arn" {
  description = "GitHub Actions 要 assume 的 IAM Role ARN（填入 GitHub Actions workflow）"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC Identity Provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "allowed_subject" {
  description = "允許的 OIDC Subject（repo + branch 組合）"
  value       = local.github_oidc_subject
}
