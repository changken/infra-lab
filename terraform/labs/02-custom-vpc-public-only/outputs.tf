#--------------------------------------------------------------
# Outputs — 之後其他 lab 可以引用這些值
#--------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

# TODO: 補完以下三個 output

# vpc_cidr_block
#   提示：從 aws_vpc.main 取 cidr_block 屬性

# public_subnet_ids
#   提示：
#     - 如果 TODO 3 用 count    → aws_subnet.public[*].id
#     - 如果 TODO 3 用 for_each → [for s in aws_subnet.public : s.id]
#                                 或 values(aws_subnet.public)[*].id

# internet_gateway_id
#   提示：從 aws_internet_gateway.main 取 id

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = var.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.main.id
}