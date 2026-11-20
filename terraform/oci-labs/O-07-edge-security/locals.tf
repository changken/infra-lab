locals {
  common_tags = {
    Project     = "infra-lab"
    Environment = "lab"
    ManagedBy   = "terraform"
    Lab         = "O-07-edge-security"
  }

  # 從 VCN CIDR 切出三個 subnet
  lb_subnet_cidr  = cidrsubnet(var.vcn_cidr, 8, 1)  # /24 public：Load Balancer
  fw_subnet_cidr  = cidrsubnet(var.vcn_cidr, 8, 5)  # /24 private：Network Firewall
  app_subnet_cidr = cidrsubnet(var.vcn_cidr, 8, 10) # /24 private：backend instances
}
