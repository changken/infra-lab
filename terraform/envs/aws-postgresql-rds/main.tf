#==============================================================
# AWS RDS PostgreSQL (Single AZ)
#
# 架構：
#   Default VPC
#   └── Default Subnets (多 AZ)
#       └── DB Subnet Group
#           └── RDS PostgreSQL 16 (Single AZ)
#               └── Security Group (port 5432, 允許 var.allowed_cidr)
#
# PostgreSQL port: 5432
# ⚠️  用完立刻 terraform destroy！RDS 按小時計費
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

resource "aws_security_group" "postgresql_rds" {
  name        = "${var.project}-pgsql-rds-sg"
  description = "Allow PostgreSQL access from allowed CIDR"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "PostgreSQL from my IP"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project}-pgsql-rds-sg" })
}

# ── DB Subnet Group ────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
  tags       = merge(local.common_tags, { Name = "${var.project}-subnet-group" })
}

# ── RDS PostgreSQL ─────────────────────────────────────────

resource "aws_db_instance" "postgresql" {
  identifier = "${var.project}-pgsql"

  # Engine
  engine         = "postgres"
  engine_version = var.engine_version

  # Instance
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  # Credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.postgresql_rds.id]
  publicly_accessible    = var.publicly_accessible
  multi_az               = false

  # Lab 設定：避免額外費用
  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = var.deletion_protection
  apply_immediately   = true

  tags = merge(local.common_tags, { Name = "${var.project}-pgsql" })
}
