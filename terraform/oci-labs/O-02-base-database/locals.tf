locals {
  common_tags = {
    Project     = "infra-lab"
    Environment = "lab"
    ManagedBy   = "terraform"
    Lab         = "O-02-base-database"
  }

  # 從 VCN CIDR 切出 DB subnet
  db_subnet_cidr = cidrsubnet(var.vcn_cidr, 8, 10) # /24
}
