locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  common_labels = {
    project     = var.project
    environment = var.environment
    managed-by  = "terraform"
  }

  # EKS cluster 尚未完全 ACTIVE 時，identity / oidc 可能會暫時是空集合。
  # 先安全取值，再由 main.tf 的 precondition 顯示較清楚的前置條件訊息。
  oidc_issuer_url = try(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, null)

  # OIDC issuer URL 去掉 https:// 前綴，用於 IAM trust policy 的 Condition key
  # 例如：oidc.eks.us-east-1.amazonaws.com/id/XXXXXXXXXX
  oidc_issuer = local.oidc_issuer_url == null ? null : trimprefix(local.oidc_issuer_url, "https://")
}
