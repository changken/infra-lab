output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC Provider created for this cluster"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "irsa_role_arn" {
  description = "IAM Role ARN assigned to the Kubernetes Service Account"
  value       = aws_iam_role.app.arn
}

output "service_account_name" {
  description = "Kubernetes Service Account name"
  value       = kubernetes_service_account.app.metadata[0].name
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "verify_command" {
  description = "Run this command to verify IRSA is working (expected: role ARN in output)"
  value       = "kubectl exec -n ${var.namespace_name} deployment/${var.project}-app -- aws sts get-caller-identity"
}

output "verify_s3_command" {
  description = "Run this to verify S3 read access via IRSA"
  value       = "kubectl exec -n ${var.namespace_name} deployment/${var.project}-app -- aws s3 ls --region ${var.region}"
}
