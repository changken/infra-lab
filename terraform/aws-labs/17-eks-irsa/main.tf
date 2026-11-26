#==============================================================
# 學習目標：IRSA（IAM Roles for Service Accounts）
#
# 前置條件：Lab 15 的 EKS Cluster 必須是 ACTIVE 狀態
#
# ⭐ 解決的問題：
#   沒有 IRSA：Pod 要存取 AWS 服務需要 hardcode 憑證（危險！）
#   有了 IRSA：Pod 透過 K8s Service Account 自動取得臨時憑證（安全！）
#
# ⭐ IRSA 運作機制（四個元件缺一不可）：
#
#   1. OIDC Provider（已預填）
#      EKS cluster 有內建 OIDC 端點，需要在 AWS IAM 中建立對應的 OIDC Provider
#      讓 AWS STS 信任 EKS 簽發的 JWT Token
#
#   2. IAM Role（trust OIDC Provider）← TODO 1
#      - Action = "sts:AssumeRoleWithWebIdentity"（不是 AssumeRole！）
#      - Principal = Federated: OIDC Provider ARN（不是 Service！）
#      - Condition：限制只有特定 namespace/service_account 才能 assume
#
#   3. Kubernetes Service Account + annotation ← TODO 4
#      - annotation "eks.amazonaws.com/role-arn" = IAM Role ARN
#      - 這個 annotation 告訴 EKS 要注入哪個 IAM Role 的憑證
#
#   4. Pod 使用 Service Account ← TODO 5
#      - spec.serviceAccountName = service_account 名稱
#      - EKS 會自動掛載 IAM 臨時憑證到 Pod
#
# ⚠️ 費用提醒：Lab 15 的 EKS 費用 $0.20/hr，本 Lab 不額外增加費用
#==============================================================


#--------------------------------------------------------------
# Data Sources（已預填）
#--------------------------------------------------------------
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}

# 取得 OIDC 端點的 TLS 憑證指紋（OIDC Provider 建立時需要）
data "tls_certificate" "eks" {
  url = local.oidc_issuer_url
}


#--------------------------------------------------------------
# OIDC Provider（已預填）
# 讓 AWS IAM 信任 EKS 的 OIDC 端點，這是 IRSA 的基礎設施層
#--------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = local.oidc_issuer_url
  tags            = local.common_tags

  lifecycle {
    precondition {
      condition     = local.oidc_issuer_url != null
      error_message = "EKS cluster 的 OIDC issuer 尚未可用。請先確認 Lab 15 cluster 已是 ACTIVE，並等待 AWS 回傳 identity.oidc.issuer 後再執行 Lab 17。"
    }
  }
}


#--------------------------------------------------------------
# TODO 1: IAM Role with OIDC Trust Policy
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# ⭐ 這是 IRSA 最關鍵的設定：IAM Role 信任 OIDC Provider 而非某個 AWS Service。
#
# 需要設定：
#   name = "${var.project}-role"
#   tags = local.common_tags
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#
#       Principal = {
#         Federated = aws_iam_openid_connect_provider.eks.arn   # ← Federated，不是 Service！
#       }
#
#       Action = "sts:AssumeRoleWithWebIdentity"   # ← WebIdentity，不是 AssumeRole！
#
#       Condition = {
#         StringEquals = {
#           "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.namespace_name}:${var.project}-sa"
#           "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
#         }
#       }
#     }]
#   })
#
# ⚠️ Condition 的 :sub 格式固定為 "system:serviceaccount:<namespace>:<sa-name>"
# ⚠️ Action 必須是 AssumeRoleWithWebIdentity，否則 Pod 無法 assume role

resource "aws_iam_role" "app" {
  # TODO
  name = "${var.project}-role"
  tags = local.common_tags
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
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.namespace_name}:${var.project}-sa"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}


#--------------------------------------------------------------
# TODO 2: IAM Policy Attachment
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
#
# 給這個 Role 附加 S3 唯讀權限，用來驗證 IRSA 是否正常運作。
#
# 需要設定：
#   role       = aws_iam_role.app.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"

resource "aws_iam_role_policy_attachment" "app" {
  # TODO
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}


#--------------------------------------------------------------
# TODO 3: Kubernetes Namespace（已學過）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace
#
# 需要設定：
#   metadata {
#     name   = var.namespace_name
#     labels = local.common_labels
#   }

resource "kubernetes_namespace" "app" {
  # TODO
  metadata {
    name   = var.namespace_name
    labels = local.common_labels
  }
}


#--------------------------------------------------------------
# TODO 4: Kubernetes Service Account（with IRSA Annotation）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account
#
# ⭐ IRSA 的關鍵：annotation 告訴 EKS 要把哪個 IAM Role 的憑證注入到使用此 SA 的 Pod
#
# 需要設定：
#   metadata {
#     name      = "${var.project}-sa"
#     namespace = kubernetes_namespace.app.metadata[0].name
#     annotations = {
#       "eks.amazonaws.com/role-arn" = aws_iam_role.app.arn   # ← 這行是 IRSA 的魔法！
#     }
#   }
#
# ⚠️ annotation key 固定為 "eks.amazonaws.com/role-arn"，寫錯就沒有效果

resource "kubernetes_service_account" "app" {
  # TODO
  metadata {
    name      = "${var.project}-sa"
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.app.arn
    }
  }
}


#--------------------------------------------------------------
# TODO 5: Kubernetes Deployment（使用 Service Account）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment
#
# ⭐ Pod spec 中指定 service_account_name，EKS 就會自動掛載 IAM 臨時憑證到容器內。
#    容器內的 AWS SDK 會自動使用這些憑證，不需要任何額外設定。
#
# 需要設定：
#   metadata {
#     name      = "${var.project}-app"
#     namespace = kubernetes_namespace.app.metadata[0].name
#     labels    = local.common_labels
#   }
#
#   spec {
#     replicas = 1
#
#     selector {
#       match_labels = { app = var.project }
#     }
#
#     template {
#       metadata {
#         labels = { app = var.project }
#       }
#       spec {
#         service_account_name = kubernetes_service_account.app.metadata[0].name  # ← 關鍵！
#
#         container {
#           name    = var.project
#           image   = "amazon/aws-cli"
#           command = ["sleep", "infinity"]   # 保持 Pod 存活，以便 kubectl exec 驗證
#         }
#       }
#     }
#   }

resource "kubernetes_deployment" "app" {
  # TODO
  metadata {
    name      = "${var.project}-app"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.common_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = var.project }
    }

    template {
      metadata {
        labels = { app = var.project }
      }
      spec {
        service_account_name = kubernetes_service_account.app.metadata[0].name

        container {
          name    = var.project
          image   = "amazon/aws-cli"
          command = ["sleep", "infinity"]
        }
      }
    }
  }
}
