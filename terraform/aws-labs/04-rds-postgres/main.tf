#==============================================================
# 學習目標：建立 RDS PostgreSQL，理解受管資料庫的設計思維
#
# 架構：
#   Default VPC
#   └── Default Subnets (多 AZ)
#       └── DB Subnet Group
#           └── RDS PostgreSQL (db.t3.micro)
#               └── Security Group (port 5432)
#
# 完成順序：1 → 2 → 3
# ⚠️  跑完立刻 destroy！開著就在計費（$0.017/小時）
#==============================================================


# 已完成：取得 Default VPC 和 Subnets（data source 不建立資源）
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}


#--------------------------------------------------------------
# TODO 1: Security Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
#
# RDS 需要一個 Security Group 控制誰能連進來。
#
# 需要設定：
#   name        → "${var.project}-rds-sg"
#   description → "Allow PostgreSQL access"
#   vpc_id      → data.aws_vpc.default.id
#
#   ingress（允許進來的流量）：
#     from_port   = var.db_port
#     to_port     = var.db_port
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]   # Lab 環境，實際上應限縮來源 IP
#
#   egress（允許出去的流量）：
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"             # -1 = all protocols
#     cidr_blocks = ["0.0.0.0/0"]
#
#   tags = local.common_tags

resource "aws_security_group" "rds" {
  # TODO
  name = "${var.project}-rds-sg"
  description = "Allow PostgreSQL access"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port = var.db_port
    to_port = var.db_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#--------------------------------------------------------------
# TODO 2: DB Subnet Group
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group
#
# RDS 要求指定放在哪些 subnet（至少跨 2 個 AZ）。
# 用 data source 取得的 default subnets 就夠了。
#
# 需要設定：
#   name       → "${var.project}-subnet-group"
#   subnet_ids → data.aws_subnets.default.ids
#   tags       = local.common_tags

resource "aws_db_subnet_group" "main" {
  # TODO
  name = "${var.project}-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 3: RDS Instance
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance
#
# 這是主體。重點參數說明：
#
# ── 引擎 ──
#   engine         → "postgres"
#   engine_version → "16"
#
# ── 規格 ──
#   instance_class    → "db.t3.micro"   （Free Tier 可用，最便宜）
#   allocated_storage → 20              （GB，Free Tier 上限）
#
# ── 資料庫設定 ──
#   db_name  → var.db_name
#   username → var.db_username
#   password → var.db_password
#   port     → var.db_port
#
# ── 網路 ──
#   db_subnet_group_name   → aws_db_subnet_group.main.name
#   vpc_security_group_ids → [aws_security_group.rds.id]
#   publicly_accessible    → true    （Lab 用，方便連線）
#
# ── 重要：Lab 環境必設 ──
#   skip_final_snapshot → true   （destroy 時不要建 snapshot，否則要額外收費）
#   deletion_protection → false  （允許 destroy）
#
# ── tags ──
#   tags = merge(local.common_tags, { Name = "${var.project}-postgres" })

resource "aws_db_instance" "main" {
  # TODO
  engine = "postgres"
  engine_version = "18"
  instance_class = "db.t3.micro"
  allocated_storage = 20
  
  db_name = var.db_name
  username = var.db_username
  password = var.db_password
  port = var.db_port
  
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible = true
  
  skip_final_snapshot = true
  deletion_protection = false

  tags = merge(local.common_tags, { Name = "${var.project}-postgres" })
}
