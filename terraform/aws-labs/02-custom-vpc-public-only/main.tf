#==============================================================
# 學習目標：自己蓋 VPC + Public Subnet（跨 2 AZ）+ IGW + Route Table
#
# 拓樸：
#
#     Internet
#         │
#     ┌───┴───┐
#     │  IGW  │
#     └───┬───┘
#         │
#   ┌─────┴──────────────────────────┐
#   │   VPC (10.0.0.0/16)            │
#   │                                │
#   │  ┌──────────────┐ ┌──────────┐ │
#   │  │ Subnet A     │ │ Subnet B │ │
#   │  │ 10.0.1.0/24  │ │10.0.2.0/24│ │
#   │  │ us-east-1a   │ │us-east-1b│ │
#   │  └──────────────┘ └──────────┘ │
#   │                                │
#   │  Route Table: 0.0.0.0/0 → IGW  │
#   └────────────────────────────────┘
#
# 完成順序：1 → 2 → 3 → 4 → 5
#==============================================================


#--------------------------------------------------------------
# TODO 1: VPC
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
#
# 需要設定的屬性：
#   - cidr_block            → 用 var.vpc_cidr
#   - enable_dns_hostnames  → 建議 true（之後 EC2 才會拿到 public DNS）
#   - enable_dns_support    → 建議 true
#   - tags                  → 用 merge(local.common_tags, { Name = "..." })

resource "aws_vpc" "main" {
  # TODO
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-vpc" })
}


#--------------------------------------------------------------
# TODO 2: Internet Gateway
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
#
# 需要設定的屬性：
#   - vpc_id  → 關聯到上面的 aws_vpc.main
#   - tags

resource "aws_internet_gateway" "main" {
  # TODO
  vpc_id = aws_vpc.main.id
  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-igw"})
}


#--------------------------------------------------------------
# TODO 3: Public Subnets（兩個，跨 AZ）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
#
# 這裡要建立 2 個 subnet。兩種寫法擇一：
#
# 寫法 A — count（簡單直觀，推薦新手）：
#   resource "aws_subnet" "public" {
#     count             = length(var.public_subnet_cidrs)
#     cidr_block        = var.public_subnet_cidrs[count.index]
#     availability_zone = var.availability_zones[count.index]
#     ...
#   }
#
# 寫法 B — for_each（更彈性，每個 subnet 有 stable key）：
#   resource "aws_subnet" "public" {
#     for_each = {
#       for idx, cidr in var.public_subnet_cidrs :
#       var.availability_zones[idx] => cidr
#     }
#     cidr_block        = each.value
#     availability_zone = each.key
#     ...
#   }
#
# 共通需要設定的屬性：
#   - vpc_id
#   - cidr_block
#   - availability_zone
#   - map_public_ip_on_launch  → true（subnet 起的 EC2 自動拿 public IP）
#   - tags

resource "aws_subnet" "public" {
  # TODO
  count = length(var.public_subnet_cidrs)
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  vpc_id = aws_vpc.main.id
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-public-subnet-${count.index + 1}" })
}


#--------------------------------------------------------------
# TODO 4: Route Table（給 public subnet 用）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
#
# 需要設定的屬性：
#   - vpc_id
#   - route 區塊（注意是 nested block，不是 attribute）：
#       cidr_block = "0.0.0.0/0"
#       gateway_id = aws_internet_gateway.main.id
#   - tags

resource "aws_route_table" "public" {
  # TODO
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  #route {
  #  cidr_block = var.vpc_cidr
  #  gateway_id = "local"
  #}
  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-public-rt" })
}


#--------------------------------------------------------------
# TODO 5: Route Table Association（把 subnet 綁到 route table）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
#
# 需要設定的屬性：
#   - subnet_id       → 每個 public subnet
#   - route_table_id  → 上面的 aws_route_table.public
#
# 提示：要為「每個 subnet」各建一筆 association。
# 用 count 或 for_each，模式跟 TODO 3 對應：
#   - TODO 3 用 count    → 這裡也用 count，aws_subnet.public[count.index].id
#   - TODO 3 用 for_each → 這裡也用 for_each，aws_subnet.public[each.key].id

resource "aws_route_table_association" "public" {
  # TODO
  count = length(var.public_subnet_cidrs)
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
