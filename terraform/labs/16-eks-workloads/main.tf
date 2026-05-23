#==============================================================
# 學習目標：用 Terraform 部署 Kubernetes Workload 到 EKS
#
# 前置條件：Lab 15 的 EKS Cluster 必須是 ACTIVE 狀態
#
# 與前面 Lab 的差異：
#   Lab 15：建立 EKS 控制平面 + 工作節點（基礎設施層）
#   Lab 16（本 lab）：在 K8s 上部署應用程式（應用層）
#
# ⭐ 新概念：
#   1. Kubernetes Terraform Provider
#      用 Terraform 管理 K8s 資源（等同於 kubectl apply -f）
#      Provider 透過 EKS data source 取得連線資訊（已預填）
#
#   2. kubernetes_namespace
#      K8s 的命名空間，用來隔離不同應用或環境
#
#   3. kubernetes_deployment
#      定義要跑幾個 Pod、用什麼 image、expose 哪個 port
#      注意三層結構：metadata → spec → template → spec → container
#
#   4. kubernetes_service（type = LoadBalancer）
#      建立 AWS ELB，讓外部流量進入 cluster
#      取代了 Lab 12 的 ALB 手動設定，由 K8s 控制器自動建立
#
# ⚠️ 費用提醒：Lab 15 的 EKS + 本 lab 的 ELB 費用合計約 $0.21/hr
#==============================================================


#--------------------------------------------------------------
# Data Sources（已預填）
# 從 AWS 取得 Lab 15 建立的 EKS cluster 連線資訊
#--------------------------------------------------------------
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}


#--------------------------------------------------------------
# TODO 1: Kubernetes Namespace
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace
#
# ⭐ Namespace 是 K8s 的隔離邊界，所有後續資源都會部署到這個 namespace。
#
# 需要設定：
#   metadata {
#     name   = var.namespace_name
#     labels = local.common_labels
#   }
#
# ⚠️ 注意：Kubernetes 資源用 labels（不是 tags），且放在 metadata block 裡

resource "kubernetes_namespace" "app" {
  # TODO
  metadata {
    name   = var.namespace_name
    labels = local.common_labels
  }
}


#--------------------------------------------------------------
# TODO 2: Kubernetes Deployment
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment
#
# ⭐ Deployment 定義 Pod 的期望狀態，K8s 會確保 replicas 個 Pod 一直在跑。
#
# 需要設定：
#   metadata {
#     name      = "${var.project}-app"
#     namespace = kubernetes_namespace.app.metadata[0].name
#     labels    = local.common_labels
#   }
#
#   spec {
#     replicas = var.replica_count
#
#     selector {
#       match_labels = { app = var.project }    # ← 必須和 template labels 一致！
#     }
#
#     template {
#       metadata {
#         labels = { app = var.project }
#       }
#       spec {
#         container {
#           name  = var.project
#           image = var.app_image
#           port {
#             container_port = 80
#           }
#         }
#       }
#     }
#   }
#
# ⚠️ selector.match_labels 和 template.metadata.labels 必須一致，否則 Deployment 無效

resource "kubernetes_deployment" "app" {
  # TODO
  metadata {
    name      = "${var.project}-app"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.common_labels
  }

  spec {
    replicas = var.replica_count

    selector {
      match_labels = { app = var.project }
    }

    template {
      metadata {
        labels = { app = var.project }
      }
      spec {
        container {
          name  = var.project
          image = var.app_image
          port {
            container_port = 80
          }
        }
      }
    }
  }
}


#--------------------------------------------------------------
# TODO 3: Kubernetes Service（LoadBalancer）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service
#
# ⭐ type = "LoadBalancer" 會讓 K8s 在 AWS 自動建立一個 ELB，對外暴露 Pod。
#    這是 K8s 的 Service 最重要的 type，取代了手動設定 ALB（Lab 12）的方式。
#
# 需要設定：
#   metadata {
#     name      = "${var.project}-svc"
#     namespace = kubernetes_namespace.app.metadata[0].name
#   }
#
#   spec {
#     selector = { app = var.project }    # ← 對應 Deployment 的 template labels
#
#     port {
#       port        = 80
#       target_port = 80
#     }
#
#     type = "LoadBalancer"
#   }
#
# ⚠️ selector 要和 Deployment 的 match_labels 完全一致，否則 Service 無法找到 Pod

resource "kubernetes_service" "app" {
  # TODO
  metadata {
    name      = "${var.project}-svc"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    selector = { app = var.project }

    port {
      port        = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }
}
