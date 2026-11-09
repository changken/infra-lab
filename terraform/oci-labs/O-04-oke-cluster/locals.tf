locals {
  common_tags = {
    Project     = "infra-lab"
    Environment = "lab"
    ManagedBy   = "terraform"
    Lab         = "O-04-oke-cluster"
  }

  # 從 VCN CIDR 切出三個 subnet
  api_subnet_cidr  = cidrsubnet(var.vcn_cidr, 12, 0) # /28：K8s API endpoint
  node_subnet_cidr = cidrsubnet(var.vcn_cidr, 8, 10) # /24：worker nodes
  lb_subnet_cidr   = cidrsubnet(var.vcn_cidr, 8, 20) # /24：Service type=LoadBalancer
}
