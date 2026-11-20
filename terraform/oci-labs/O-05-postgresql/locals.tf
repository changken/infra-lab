locals {
  common_tags = {
    Project     = "infra-lab"
    Environment = "lab"
    ManagedBy   = "terraform"
    Lab         = "O-05-postgresql"
  }

  # 從 VCN CIDR 切出 PostgreSQL DB system 用的 private subnet
  psql_subnet_cidr = cidrsubnet(var.vcn_cidr, 8, 10) # /24
}
