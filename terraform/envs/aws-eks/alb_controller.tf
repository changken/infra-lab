#==============================================================
# AWS Load Balancer Controller — IRSA 基礎設施
#
# Terraform 負責：
#   1. EKS OIDC Provider（IRSA 必要條件）
#   2. IAM Role（使用 IRSA，讓 K8s ServiceAccount 取得 AWS 權限）
#   3. IAM Policy（從官方 GitHub 抓取，確保版本一致）
#
# Helm 安裝（apply 後手動執行，見 README）：
#   helm install aws-load-balancer-controller ...
#==============================================================

# ── OIDC Provider（EKS IRSA 必要條件）─────────────────────

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = local.common_tags
}

# ── IAM Policy（從官方 GitHub 取得，對應 var.aws_lbc_version）

data "http" "aws_lbc_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${var.aws_lbc_version}/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "aws_lbc" {
  name        = "${local.name_prefix}-aws-lbc-policy"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = data.http.aws_lbc_iam_policy.response_body

  tags = local.common_tags
}

# ── IAM Role（IRSA：讓 kube-system/aws-load-balancer-controller 使用）

resource "aws_iam_role" "aws_lbc" {
  name = "${local.name_prefix}-aws-lbc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "aws_lbc" {
  role       = aws_iam_role.aws_lbc.name
  policy_arn = aws_iam_policy.aws_lbc.arn
}
