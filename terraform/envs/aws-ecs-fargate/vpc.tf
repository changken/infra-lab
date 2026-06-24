#==============================================================
# VPC + Public Subnets（無 NAT Gateway）
#
# EKS vs ECS Fargate 架構差異：
#   EKS:    Nodes 在 private subnet，需 NAT Gateway 出外網 ($0.045/hr)
#   Fargate: Tasks 在 public subnet，assign_public_ip = ENABLED
#            可直接出外網 pull ECR image、呼叫 Secrets Manager
#            省下 NAT Gateway 費用 ($32/月)
#
# ⚠️ 生產環境建議：
#   Tasks 放 private subnet + VPC Endpoints（ECR, S3, Secrets Manager）
#   此 lab 採用 public subnet 以降低學習成本
#==============================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}

# ── Internet Gateway ────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-igw" })
}

# ── Public Subnets（ALB + Fargate Tasks 共用）──────────────

resource "aws_subnet" "public" {
  for_each = local.public_subnet_cidrs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false # Task ENI 的 public IP 由 ECS Service 的 assign_public_ip 控制

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${each.key}"
    Tier = "public"
  })
}

# ── Route Table ─────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
