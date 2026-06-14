output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "public_subnet_ids" {
  description = "Map of AZ => public subnet ID"
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "private_subnet_ids" {
  description = "Map of AZ => private subnet ID"
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}

output "public_route_table_id" {
  description = "The ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "The ID of the private route table"
  value       = aws_route_table.private.id
}

output "k3s_security_group_id" {
  description = "The ID of the k3s security group"
  value       = aws_security_group.k3s_nodes.id
}

output "internal_security_group_id" {
  description = "The ID of the internal security group"
  value       = aws_security_group.internal.id
}

output "k3s_key_pair_name" {
  description = "The name of the k3s key pair"
  value       = aws_key_pair.k3s.key_name
}