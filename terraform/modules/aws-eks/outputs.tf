output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "Additional security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "cluster_role_arn" {
  description = "IAM role ARN used by the EKS control plane"
  value       = aws_iam_role.cluster.arn
}

output "compute_mode" {
  description = "Enabled EKS compute mode"
  value       = var.compute_mode
}

output "node_group_name" {
  description = "EKS managed node group name"
  value       = local.is_ec2 ? aws_eks_node_group.main[0].node_group_name : null
}

output "node_role_arn" {
  description = "IAM role ARN used by EKS worker nodes"
  value       = local.is_ec2 ? aws_iam_role.node[0].arn : null
}

output "fargate_profile_name" {
  description = "EKS Fargate profile name"
  value       = local.is_fargate ? aws_eks_fargate_profile.main[0].fargate_profile_name : null
}

output "fargate_pod_execution_role_arn" {
  description = "IAM role ARN used by EKS Fargate pods"
  value       = local.is_fargate ? aws_iam_role.fargate_pod_execution[0].arn : null
}

output "kubeconfig_command" {
  description = "Run this command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
}
