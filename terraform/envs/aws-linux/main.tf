#==============================================================
# env: aws-linux — Amazon Linux 2023 開發 / 跳板機
#
# 拓樸：
#   你的電腦 --SSH (22)--> AL2023 Spot (Public Subnet)
#                               |
#                          (可延伸連接 Private 資源)
#                               ↓
#                    RDS / Aurora / EKS nodes (Private Subnet)
#==============================================================

# ── 1. VPC & Subnets ───────────────────────────────────────

module "vpc" {
  source = "../../modules/aws-vpc"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  personal_pc_cidr     = var.my_ip
}

# ── 2. Linux Spot (Bastion / Dev) ─────────────────────────

module "linux" {
  source = "../../modules/aws-linux"

  region      = var.region
  name_prefix = var.project
  environment = var.environment
  my_ip       = var.my_ip

  vpc_id    = module.vpc.vpc_id
  subnet_id = values(module.vpc.public_subnet_ids)[0]

  instance_type    = var.instance_type
  market_type      = var.market_type
  root_volume_size = var.root_volume_size
}
