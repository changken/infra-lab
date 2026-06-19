#==============================================================
# AWS Aurora PostgreSQL Module - Main Configuration
#==============================================================

# ── Security Group ─────────────────────────────────────────

resource "aws_security_group" "aurora" {
  name        = "${var.project}-sg"
  description = "Security Group for Aurora PostgreSQL Cluster"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Access from allowed CIDRs"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = var.allowed_security_groups
    content {
      description     = "Access from source SG"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project}-sg" })
}

# ── DB Subnet Group ────────────────────────────────────────

resource "aws_db_subnet_group" "aurora" {
  name        = "${var.project}-subnet-group"
  description = "Database subnet group for Aurora PGSQL"
  subnet_ids  = var.subnet_ids

  tags = merge(local.common_tags, { Name = "${var.project}-subnet-group" })
}

# ── Custom Parameter Groups ───────────────────────────────

resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.project}-cluster-pg"
  family      = "aurora-postgresql${split(".", var.engine_version)[0]}"
  description = "Aurora PGSQL custom cluster parameter group"

  parameter {
    name  = "timezone"
    value = "Asia/Taipei"
  }

  tags = local.common_tags
}

resource "aws_db_parameter_group" "aurora" {
  name        = "${var.project}-instance-pg"
  family      = "aurora-postgresql${split(".", var.engine_version)[0]}"
  description = "Aurora PGSQL custom instance parameter group"

  tags = local.common_tags
}

# ── Aurora Cluster ─────────────────────────────────────────

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${var.project}-cluster"

  engine         = "aurora-postgresql"
  engine_version = var.engine_version

  database_name   = var.db_name
  master_username = var.db_username
  master_password = var.db_password
  port            = 5432

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.instance_class == "db.serverless" ? [1] : []
    content {
      min_capacity = var.serverless_min_capacity
      max_capacity = var.serverless_max_capacity
    }
  }

  storage_encrypted = true

  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection

  tags = local.common_tags
}

# ── Aurora Cluster Instances ──────────────────────────────

resource "aws_rds_cluster_instance" "aurora" {
  count = var.cluster_size

  identifier         = "${var.project}-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id

  engine         = aws_rds_cluster.aurora.engine
  engine_version = aws_rds_cluster.aurora.engine_version

  instance_class       = var.instance_class
  db_subnet_group_name = aws_db_subnet_group.aurora.name

  db_parameter_group_name = aws_db_parameter_group.aurora.name

  publicly_accessible = false

  tags = merge(local.common_tags, { Name = "${var.project}-instance-${count.index + 1}" })
}
