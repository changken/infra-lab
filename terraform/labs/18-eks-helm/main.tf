#==============================================================
# 學習目標：用 Terraform Helm Provider 部署 Helm Chart 到 EKS
#
# 前置條件：Lab 15 的 EKS Cluster 必須是 ACTIVE 狀態
#
# 與前面 Lab 的差異：
#   Lab 16：手動定義每個 K8s 資源（Deployment, Service...）
#   Lab 18（本 lab）：用 Helm Chart 一次部署整套應用，靠 values 客製化
#
# ⭐ 新概念：
#   1. helm_release 資源
#      等同於 `helm install <name> <chart> --repo <repo>`
#      Terraform 管理 Helm release 的生命週期（install / upgrade / uninstall）
#
#   2. set {} block（覆寫 Chart Values）
#      等同於 `helm install ... --set key=value`
#      用來客製化 Chart 的預設設定，不需要修改 Chart 本身
#
#   3. create_namespace = true
#      讓 Helm 自動建立 namespace（不需要另外定義 kubernetes_namespace）
#
#   4. repository（Helm Repository URL）
#      Chart 來源，類似 apt/yum repository
#      可用 `helm repo add` 在本地管理，Terraform 直接在 resource 中指定
#
# ⚠️ 費用提醒：Lab 15 的 EKS 費用 $0.20/hr，本 Lab 額外建立 ELB $0.008/hr
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


#--------------------------------------------------------------
# TODO 1: Helm Release — metrics-server
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release
# Chart: https://artifacthub.io/packages/helm/metrics-server/metrics-server
#
# ⭐ metrics-server 是 kubectl top nodes/pods 的後端，EKS 預設不安裝。
#    這是最簡單的 helm_release 範例，只需要一個 set block。
#
# 需要設定：
#   name             = "metrics-server"
#   repository       = "https://kubernetes-sigs.github.io/metrics-server/"
#   chart            = "metrics-server"
#   namespace        = "kube-system"     # 裝在 K8s 系統 namespace
#   version          = var.metrics_server_version
#   create_namespace = false             # kube-system 已存在
#
#   set {
#     name  = "args[0]"
#     value = "--kubelet-insecure-tls"   # EKS 特有需求：kubelet 憑證非公開 CA 簽發
#   }
#
# ⚠️ EKS 上必須加 --kubelet-insecure-tls，否則 metrics-server 無法取得節點資料

resource "helm_release" "metrics_server" {
  # TODO
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  namespace        = "kube-system"
  version          = var.metrics_server_version
  create_namespace = false

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}


#--------------------------------------------------------------
# TODO 2: Helm Release — ingress-nginx（多個 set blocks）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release
# Chart: https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx
#
# ⭐ ingress-nginx 是最常用的 K8s Ingress Controller。
#    部署後會在 AWS 自動建立 ELB，讓 Ingress 資源能對外暴露服務。
#
# 需要設定：
#   name             = "ingress-nginx"
#   repository       = "https://kubernetes.github.io/ingress-nginx"
#   chart            = "ingress-nginx"
#   namespace        = "ingress-nginx"
#   version          = var.ingress_nginx_version
#   create_namespace = true              # ingress-nginx namespace 不存在，讓 Helm 建立
#
#   set {
#     name  = "controller.service.type"
#     value = "LoadBalancer"             # 建立 AWS ELB
#   }
#
#   set {
#     name  = "controller.replicaCount"
#     value = "1"                        # Lab 用，省 EC2 資源
#   }
#
#   set {
#     name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
#     value = "nlb"                      # 使用 NLB（比 CLB 便宜且更好）
#   }
#
# ⚠️ set.name 中的 . 需要跳脫：annotation key 中的 . 改寫成 \\.
# ⚠️ create_namespace = true 讓 Helm 自動建 namespace，不需要另外定義 kubernetes_namespace

resource "helm_release" "ingress_nginx" {
  # TODO
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  version          = var.ingress_nginx_version
  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.replicaCount"
    value = "1"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }
}
