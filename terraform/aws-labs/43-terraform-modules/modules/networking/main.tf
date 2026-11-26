#==============================================================
# Module: networking
# 輸入：project, environment, vpc_cidr, public_subnet_cidrs,
#       availability_zones, tags
# 輸出：vpc_id, public_subnet_ids, vpc_cidr_block
#==============================================================

#--------------------------------------------------------------
# TODO 1: VPC + Internet Gateway + Public Subnets + Route Table
#--------------------------------------------------------------
# 模組內所有值從 var.xxx 取得（不可 hardcode，不可引用 module 外的資源）
#
# [VPC]
#   cidr_block           = var.vpc_cidr
#   enable_dns_hostnames = true
#   enable_dns_support   = true
#   tags = merge(var.tags, { Name = "${var.project}-${var.environment}-vpc" })
#
# [Internet Gateway]
#   vpc_id = aws_vpc.main.id
#   tags   = merge(var.tags, { Name = "${var.project}-${var.environment}-igw" })
#
# [Public Subnets]（count 建立多個 subnet，每個 AZ 一個）
#   count                   = length(var.public_subnet_cidrs)
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = var.public_subnet_cidrs[count.index]   ← 用 count.index 取 list 元素
#   availability_zone       = var.availability_zones[count.index]
#   map_public_ip_on_launch = true
#   tags = merge(var.tags, { Name = "${var.project}-${var.environment}-public-${count.index + 1}" })
#
# [Route Table]（所有 public subnet 共用一個）
#   vpc_id = aws_vpc.main.id
#   tags   = merge(var.tags, { Name = "${var.project}-${var.environment}-public-rt" })
#
# [Route]（預設路由 → Internet Gateway）
#   route_table_id         = aws_route_table.public.id
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = aws_internet_gateway.main.id
#
# [Route Table Associations]（count，每個 subnet 關聯到同一個 route table）
#   count          = length(var.public_subnet_cidrs)
#   subnet_id      = aws_subnet.public[count.index].id
#   route_table_id = aws_route_table.public.id
#
# ⚠️ 注意：
#   - 模組內的 tags 用 merge(var.tags, {...}) 合併呼叫者傳入的 tags 和模組內定義的 Name
#   - count 的資源用 [count.index] 取值，輸出用 [*] 展開為 list（見 outputs.tf）
#   - 模組沒有 data "aws_availability_zones"，AZ 由呼叫者決定（提高模組可攜性）

resource "aws_vpc" "main" {
  # TODO
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(var.tags, { Name = "${var.project}-${var.environment}-vpc" })
}

resource "aws_internet_gateway" "main" {
  # TODO
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.project}-${var.environment}-igw" })
}

resource "aws_subnet" "public" {
  # TODO（count）
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.project}-${var.environment}-public-${count.index + 1}" })
}

resource "aws_route_table" "public" {
  # TODO
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.project}-${var.environment}-public-rt" })
}

resource "aws_route" "internet" {
  # TODO
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  # TODO（count）
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
