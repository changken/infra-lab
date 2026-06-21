#==============================================================
# AWS EKS Cluster + Managed Node Group
#
# 架構：
#   Custom VPC
#   ├── Public Subnets  → Internet Gateway, NAT GW, ALB (by LBC)
#   └── Private Subnets → EKS Nodes (SPOT t3.medium × 2)
#
# ⚠️  EKS Control Plane $0.10/hr + NAT GW $0.045/hr，用完立刻 destroy！
#==============================================================

data "aws_caller_identity" "current" {}

# ── IAM: EKS Cluster Role ───────────────────────────────────

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

# ── IAM: Node Role ──────────────────────────────────────────

resource "aws_iam_role" "node" {
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

# ── EKS Cluster ─────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name    = local.cluster_name
  version = var.kubernetes_version

  role_arn = aws_iam_role.cluster.arn

  access_config {
    # API_AND_CONFIG_MAP：支援 access entries 也保留 aws-auth ConfigMap 相容性
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  vpc_config {
    # Control plane ENI 放在所有 subnets；nodes 只用 private subnets
    subnet_ids = concat(
      [for s in aws_subnet.public : s.id],
      [for s in aws_subnet.private : s.id],
    )
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]

  tags = local.common_tags
}

# ── EKS Console Access (可在 AWS Console 看 Pods / Nodes) ───

resource "aws_eks_access_entry" "caller" {
  count = var.enable_console_access ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"

  tags = local.common_tags
}

resource "aws_eks_access_policy_association" "caller_admin" {
  count = var.enable_console_access ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.caller]
}

# ── Managed Node Group（放在 private subnets）───────────────

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [for s in aws_subnet.private : s.id]
  instance_types  = var.node_instance_types
  capacity_type   = var.node_capacity_type
  disk_size       = var.node_disk_size

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
