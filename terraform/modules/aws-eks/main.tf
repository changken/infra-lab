#==============================================================
# EKS Template Module
#
# 建立最小可用的 EKS Cluster，並可選擇 EC2 Managed Node Group 或 EKS Fargate Profile。
# 使用者需提供既有 VPC 與至少兩個 subnet IDs，避免本模組隱含建立 NAT Gateway。
#==============================================================

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "cluster" {
  name = "${local.name_prefix}-eks-cluster-role"

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
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node" {
  count = local.is_ec2 ? 1 : 0

  name = "${local.name_prefix}-eks-node-role"

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

resource "aws_iam_role_policy_attachment" "node_worker" {
  count = local.is_ec2 ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  count = local.is_ec2 ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  count = local.is_ec2 ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role" "fargate_pod_execution" {
  count = local.is_fargate ? 1 : 0

  name = "${local.name_prefix}-eks-fargate-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  count = local.is_fargate ? 1 : 0

  role       = aws_iam_role.fargate_pod_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_security_group" "cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "Legacy additional security group for EKS cluster migration"
  vpc_id      = data.aws_vpc.selected.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  /*lifecycle {
    prevent_destroy = true
  }*/

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-eks-cluster-sg"
    Purpose = "legacy-eks-cluster-sg-migration"
  })
}

resource "aws_eks_cluster" "main" {
  name     = "${local.name_prefix}-eks"
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  access_config {
    authentication_mode = var.authentication_mode
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
    public_access_cidrs     = var.public_access_cidrs
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]

  tags = local.common_tags
}

resource "aws_eks_access_entry" "console_viewer" {
  for_each = local.console_viewer_principal_arns

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = local.common_tags
}

resource "aws_eks_access_policy_association" "console_viewer" {
  for_each = aws_eks_access_entry.console_viewer

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value.principal_arn
  policy_arn    = var.console_viewer_access_policy_arn

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_node_group" "main" {
  count = local.is_ec2 ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node[0].arn
  subnet_ids      = local.node_subnet_ids
  instance_types  = var.node_instance_types
  capacity_type   = var.node_capacity_type
  disk_size       = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker[0],
    aws_iam_role_policy_attachment.node_cni[0],
    aws_iam_role_policy_attachment.node_ecr[0],
  ]

  tags = local.common_tags
}

resource "aws_eks_fargate_profile" "main" {
  count = local.is_fargate ? 1 : 0

  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "${local.name_prefix}-${var.fargate_profile_name}"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution[0].arn
  subnet_ids             = local.fargate_subnet_ids

  dynamic "selector" {
    for_each = var.fargate_selectors

    content {
      namespace = selector.value.namespace
      labels    = selector.value.labels
    }
  }

  depends_on = [aws_iam_role_policy_attachment.fargate_pod_execution[0]]

  tags = local.common_tags
}
