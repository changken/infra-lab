#==============================================================
# 學習目標：EKS Cluster + Managed Node Group
#
# 與前面 Lab 的差異：
#   Lab 11-14：ECS（AWS 託管控制平面，無需設定 K8s）
#   Lab 15（本 lab）：EKS（你自己的 Kubernetes 控制平面 + 工作節點）
#
# ⭐ 新概念：
#   1. 兩個不同的 IAM Role：
#      - Cluster Role（trust: eks.amazonaws.com）：控制平面用
#      - Node Role（trust: ec2.amazonaws.com）：工作節點用
#      兩者 Principal 不同，絕對不要搞混！
#
#   2. aws_eks_cluster：定義控制平面
#      - vpc_config.subnet_ids 告訴 EKS 可以跑在哪些 subnet
#      - depends_on cluster role attachment（否則 apply 順序出問題）
#
#   3. aws_eks_node_group：定義工作節點 Managed Node Group
#      - scaling_config：desired/min/max 三個參數
#      - depends_on 三個 Node policy attachments（缺一不可）
#
#   4. kubeconfig：apply 後需執行 aws eks update-kubeconfig 才能用 kubectl
#
# ⚠️ 費用警告：
#   EKS Control Plane $0.10/hr + t3.medium × 2 = $0.094/hr
#   合計約 $0.20/hr，絕對不能過夜！一日 Sprint，操作完立刻 destroy！
#==============================================================


#--------------------------------------------------------------
# Data Sources
#--------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  # ⭐ 過濾：只選擇 EKS 支持的可用區（排除 us-east-1e）
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}


#--------------------------------------------------------------
# TODO 1: EKS Cluster IAM Role
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
#
# ⭐ EKS 控制平面需要一個 IAM Role，trust principal 是 eks.amazonaws.com（不是 ecs-tasks！）
#
# aws_iam_role.cluster 需要設定：
#   name               = "${var.project}-cluster-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action    = "sts:AssumeRole"
#       Effect    = "Allow"
#       Principal = { Service = "eks.amazonaws.com" }
#     }]
#   })
#   tags = local.common_tags
#
# aws_iam_role_policy_attachment.cluster 需要設定：
#   role       = aws_iam_role.cluster.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

resource "aws_iam_role" "cluster" {
  # TODO
  name = "${var.project}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  # TODO
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


#--------------------------------------------------------------
# TODO 2: EKS Node Group IAM Role
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
# ⭐ 工作節點（EC2）需要一個 IAM Role，trust principal 是 ec2.amazonaws.com
#
# 需要設定：
#   name               = "${var.project}-node-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action    = "sts:AssumeRole"
#       Effect    = "Allow"
#       Principal = { Service = "ec2.amazonaws.com" }
#     }]
#   })
#   tags = local.common_tags
#
# ⚠️ 注意：Principal 是 ec2.amazonaws.com，不是 eks.amazonaws.com

resource "aws_iam_role" "node" {
  # TODO
  name = "${var.project}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = local.common_tags
}


#--------------------------------------------------------------
# Node Group Policy Attachments（已預填，三個 policy 都必須）
#--------------------------------------------------------------
# 這三個 attachment 是固定搭配，不需要修改，已幫你填好

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


#--------------------------------------------------------------
# TODO 3: EKS Cluster
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster
#
# ⭐ 定義 Kubernetes 控制平面。
#
# 需要設定：
#   name       = var.project
#   version    = var.kubernetes_version
#   role_arn   = aws_iam_role.cluster.arn
#
#   vpc_config {
#     subnet_ids = data.aws_subnets.default.ids
#   }
#
#   depends_on = [aws_iam_role_policy_attachment.cluster]
#   tags       = local.common_tags
#
# ⚠️ 注意：depends_on 必須寫，否則 IAM Role 還沒 ready 就 apply EKS 會失敗
# ⚠️ EKS 控制平面啟動需要 10-15 分鐘，請耐心等候

resource "aws_eks_cluster" "main" {
  # TODO
  name     = var.project
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = data.aws_subnets.default.ids
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
  tags       = local.common_tags
}


#--------------------------------------------------------------
# TODO 4: EKS Node Group（Managed Node Group）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group
#
# ⭐ Managed Node Group 讓 AWS 自動管理 EC2 工作節點的生命週期。
#
# 需要設定：
#   cluster_name    = aws_eks_cluster.main.name
#   node_group_name = "${var.project}-nodes"
#   node_role_arn   = aws_iam_role.node.arn
#   subnet_ids      = data.aws_subnets.default.ids
#   instance_types  = [var.node_instance_type]
#
#   scaling_config {
#     desired_size = var.node_desired_size
#     min_size     = var.node_min_size
#     max_size     = var.node_max_size
#   }
#
#   depends_on = [
#     aws_iam_role_policy_attachment.node_worker,
#     aws_iam_role_policy_attachment.node_cni,
#     aws_iam_role_policy_attachment.node_ecr,
#   ]
#   tags = local.common_tags
#
# ⚠️ depends_on 三個 policy attachment 缺一不可（少了 CNI 節點無法加入 cluster）

resource "aws_eks_node_group" "main" {
  # TODO
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = data.aws_subnets.default.ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  tags = local.common_tags
}
