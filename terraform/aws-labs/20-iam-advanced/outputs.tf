output "developer_role_arn" {
  description = "Developer IAM Role ARN (with permission boundary)"
  value       = aws_iam_role.developer.arn
}

output "permission_boundary_arn" {
  description = "Permission Boundary Policy ARN"
  value       = aws_iam_policy.permission_boundary.arn
}

output "dev_bucket_name" {
  description = "S3 bucket tagged Team=dev (policy should ALLOW access)"
  value       = aws_s3_bucket.dev.bucket
}

output "ops_bucket_name" {
  description = "S3 bucket tagged Team=ops (policy should DENY access)"
  value       = aws_s3_bucket.ops.bucket
}

output "simulate_allow_command" {
  description = "Simulate: can the developer role describe EC2 in the allowed region?"
  value       = <<-CMD
    aws iam simulate-principal-policy \
      --policy-source-arn ${aws_iam_role.developer.arn} \
      --action-names ec2:DescribeInstances \
      --resource-arns "*" \
      --context-entries "ContextKeyName=aws:RequestedRegion,ContextKeyValues=${var.region},ContextKeyType=stringList"
  CMD
}

output "simulate_deny_command" {
  description = "Simulate: can the developer role create an IAM user? (should be DENIED)"
  value       = <<-CMD
    aws iam simulate-principal-policy \
      --policy-source-arn ${aws_iam_role.developer.arn} \
      --action-names iam:CreateUser \
      --resource-arns "*"
  CMD
}

output "simulate_boundary_command" {
  description = "Simulate: boundary blocks EC2 in wrong region even if identity policy allows it"
  value       = <<-CMD
    aws iam simulate-principal-policy \
      --policy-source-arn ${aws_iam_role.developer.arn} \
      --action-names ec2:DescribeInstances \
      --resource-arns "*" \
      --context-entries "ContextKeyName=aws:RequestedRegion,ContextKeyValues=eu-west-1,ContextKeyType=stringList"
  CMD
}
