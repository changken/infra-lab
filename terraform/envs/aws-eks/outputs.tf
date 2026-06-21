# ── EKS ─────────────────────────────────────────────────────

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "node_group_status" {
  description = "Node group current status"
  value       = aws_eks_node_group.main.status
}

output "kubeconfig_command" {
  description = "設定 kubectl 的指令"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
}

# ── VPC ─────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB 用)"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs (Node Group 用)"
  value       = [for s in aws_subnet.private : s.id]
}

output "nat_gateway_ip" {
  description = "NAT Gateway 的 Elastic IP"
  value       = aws_eip.nat.public_ip
}

# ── ECR ─────────────────────────────────────────────────────

output "ecr_repository_url" {
  description = "ECR repository URL（docker push 用）"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_login_command" {
  description = "ECR 登入指令"
  value       = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app.repository_url}"
}

# ── AWS Load Balancer Controller ────────────────────────────

output "aws_lbc_role_arn" {
  description = "AWS LBC IAM Role ARN（Helm 安裝時需要）"
  value       = aws_iam_role.aws_lbc.arn
}

output "aws_lbc_helm_command" {
  description = "安裝 AWS Load Balancer Controller 的 Helm 指令"
  value       = <<-EOT
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
      -n kube-system \
      --set clusterName=${aws_eks_cluster.main.name} \
      --set serviceAccount.create=true \
      --set serviceAccount.name=aws-load-balancer-controller \
      --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${aws_iam_role.aws_lbc.arn} \
      --set region=${var.region} \
      --set vpcId=${aws_vpc.main.id}
  EOT
}
