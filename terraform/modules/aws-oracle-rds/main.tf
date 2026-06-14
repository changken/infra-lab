#==============================================================
# AWS RDS Oracle SE2 Module
#
# 架構：
#   Default VPC
#   └── Default Subnets (多 AZ)
#       └── DB Subnet Group
#           └── RDS Oracle SE2 (License Included)
#               └── Security Group (port 1521, 允許 var.allowed_cidr)
#
# Oracle port: 1521 (SQL*Net / JDBC Thin)
# ⚠️  用完立刻 terraform destroy！Oracle SE2 費用比 Postgres 高 3-5x
#==============================================================

# ── Default VPC / Subnets ──────────────────────────────────

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ── Security Group ─────────────────────────────────────────

resource "aws_security_group" "oracle_rds" {
  name        = "${var.project}-oracle-rds-sg"
  description = "Allow Oracle SQL*Net access from allowed CIDR"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Oracle SQL*Net"
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project}-oracle-rds-sg" })
}

# ── DB Subnet Group ────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
  tags       = merge(local.common_tags, { Name = "${var.project}-subnet-group" })
}

# ── RDS Oracle SE2 ─────────────────────────────────────────

resource "aws_db_instance" "oracle" {
  identifier = "${var.project}-oracle"

  # Engine
  engine         = "oracle-se2"
  engine_version = var.engine_version
  license_model  = var.license_model

  # Instance
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  # Credentials
  db_name  = var.db_name   # Oracle SID
  username = var.db_username
  password = var.db_password
  port     = 1521

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.oracle_rds.id]
  publicly_accessible    = var.publicly_accessible
  multi_az               = var.multi_az

  # Lab 設定：避免額外費用
  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = var.deletion_protection

  # Oracle 需要此設定才能公開存取
  apply_immediately = true

  tags = merge(local.common_tags, { Name = "${var.project}-oracle" })
}
