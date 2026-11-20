locals {
  common_tags = {
    Project     = "infra-lab"
    Environment = "lab"
    ManagedBy   = "terraform"
    Lab         = "O-04-mysql-heatwave"
  }

  # 從 VCN CIDR 切出 MySQL DB system 用的 private subnet
  mysql_subnet_cidr = cidrsubnet(var.vcn_cidr, 8, 10) # /24
}
