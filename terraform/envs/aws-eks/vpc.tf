#==============================================================
# VPC + Public/Private Subnets + NAT Gateway
#
# EKS 最佳實踐：
#   - Node Group 放 private subnets（不直接暴露）
#   - ALB 放 public subnets（由 AWS LBC 自動建立）
#   - Single NAT GW（節省費用，$0.045/hr）
#
# Subnet tags 讓 AWS Load Balancer Controller 能自動發現 subnets：
#   kubernetes.io/role/elb             = "1" → 公開 ALB 用
#   kubernetes.io/role/internal-elb    = "1" → 內部 ALB 用
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

# ── Public Subnets ──────────────────────────────────────────

resource "aws_subnet" "public" {
  for_each = local.public_subnet_cidrs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                          = "${local.name_prefix}-public-${each.key}"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })
}

# ── Private Subnets ─────────────────────────────────────────

resource "aws_subnet" "private" {
  for_each = local.private_subnet_cidrs

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(local.common_tags, {
    Name                                          = "${local.name_prefix}-private-${each.key}"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    # Karpenter EC2NodeClass subnetSelectorTerms 用此 tag 發現 private subnets
    "karpenter.sh/discovery"                      = local.cluster_name
  })
}

# ── NAT Gateway (single AZ 省錢) ────────────────────────────

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.azs[0]].id

  tags       = merge(local.common_tags, { Name = "${local.name_prefix}-nat" })
  depends_on = [aws_internet_gateway.main]
}

# ── Route Tables ────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public-rt" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
