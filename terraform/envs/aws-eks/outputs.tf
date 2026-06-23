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

# ── Karpenter ───────────────────────────────────────────────

output "karpenter_role_arn" {
  description = "Karpenter Controller IRSA Role ARN（Helm values 用）"
  value       = aws_iam_role.karpenter.arn
}

output "karpenter_node_role_name" {
  description = "Karpenter Node IAM Role 名稱（EC2NodeClass spec.role 用）"
  value       = aws_iam_role.karpenter_node.name
}

output "karpenter_interruption_queue_name" {
  description = "SQS Queue 名稱（Karpenter Helm settings.interruptionQueue 用）"
  value       = aws_sqs_queue.karpenter_interruption.name
}

output "karpenter_helm_command" {
  description = "安裝 Karpenter 的 Helm 指令"
  value       = <<-EOT
    # 1. 加入 Helm repo
    helm repo add karpenter https://charts.karpenter.sh
    helm repo update

    # 2. 安裝 Karpenter controller
    helm install karpenter karpenter/karpenter \
      --namespace karpenter --create-namespace \
      --version ${var.karpenter_version} \
      --set "settings.clusterName=${aws_eks_cluster.main.name}" \
      --set "settings.interruptionQueue=${aws_sqs_queue.karpenter_interruption.name}" \
      --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${aws_iam_role.karpenter.arn}" \
      --set "controller.resources.requests.cpu=250m" \
      --set "controller.resources.requests.memory=256Mi" \
      --wait

    # 3. 套用 NodeClass + NodePool（見 k8s/karpenter/）
    kubectl apply -f k8s/karpenter/ec2nodeclass.yaml
    kubectl apply -f k8s/karpenter/nodepool.yaml
  EOT
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
