#==============================================================
# Lab 48 - Aurora + Windows Bastion 整合範例
# 架構：aws-vpc + aws-windows-spot + aws-aurora-postgresql
#
# 拓樸：
#   你的電腦 --RDP--> Windows Spot (Public Subnet)
#                          |
#                        5432
#                          ↓
#                   Aurora PostgreSQL (Private Subnet)
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

# ── 2. Windows Spot (Bastion) ─────────────────────────────

module "windows" {
  source = "../../modules/aws-windows-spot"

  region      = var.region
  name_prefix = "${var.project}-bastion"
  environment = var.environment
  my_ip       = var.my_ip

  # 掛到自訂 VPC 的 Public Subnet（取第一個 AZ 的 Public Subnet）
  vpc_id    = module.vpc.vpc_id
  subnet_id = values(module.vpc.public_subnet_ids)[0]

  instance_type    = var.windows_instance_type
  market_type      = var.windows_market_type
  root_volume_size = 50
}

# ── 3. Aurora PostgreSQL (Private Subnet) ─────────────────

module "aurora" {
  source = "../../modules/aws-aurora-postgresql"

  region      = var.region
  project     = "${var.project}-aurora"
  environment = var.environment

  # 共用同一個 VPC，放在 Private Subnet
  vpc_id     = module.vpc.vpc_id
  subnet_ids = values(module.vpc.private_subnet_ids)

  # 只允許 Windows Bastion 的 SG 連入 5432
  allowed_security_groups = [module.windows.security_group_id]

  engine_version          = var.aurora_engine_version
  instance_class          = "db.serverless"
  serverless_min_capacity = var.aurora_min_acu
  serverless_max_capacity = var.aurora_max_acu
  cluster_size            = 1

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 1
}
