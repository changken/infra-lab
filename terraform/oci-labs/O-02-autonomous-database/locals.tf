locals {
  common_tags = {
    Project     = "infra-lab"
    Environment = "lab"
    ManagedBy   = "terraform"
    Lab         = "O-02-autonomous-database"
  }

  # 從 VCN CIDR 切出 ADB private endpoint 用的 subnet
  adb_subnet_cidr = cidrsubnet(var.vcn_cidr, 8, 10) # /24
}
