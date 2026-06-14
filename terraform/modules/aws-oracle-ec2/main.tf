#==============================================================
# aws-oracle-ec2
#
# 架構：
#   Default VPC → EC2 (AL2023) → Docker → gvenzl/oracle-xe:21-slim
#
# 費用比較（us-east-1）：
#   RDS Oracle SE2 LI db.t3.medium  ~$0.170/hr  (含授權)
#   EC2 t3.medium + Docker           ~$0.042/hr  (省 4x)
#
# Oracle XE 限制（lab 完全夠用）：
#   2 CPU、2GB RAM 使用上限、12GB 資料上限
#
# 連線：
#   JDBC: jdbc:oracle:thin:@//<public-ip>:1521/XEPDB1
#   port 5500: Oracle EM Express (Web UI)
#==============================================================

# ── AMI: Amazon Linux 2023 ─────────────────────────────────

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

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

resource "aws_security_group" "oracle_ec2" {
  name        = "${var.project}-sg"
  description = "Oracle XE on Docker"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Oracle SQL*Net"
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "Oracle EM Express"
    from_port   = 5500
    to_port     = 5500
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project}-sg" })
}

# ── EC2 Instance ───────────────────────────────────────────

resource "aws_instance" "oracle" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.oracle_ec2.id]
  associate_public_ip_address = true

  # gp3 30GB：21-full image ~10GB + Oracle data + sample schemas
  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    oracle_password = var.oracle_password
  })

  tags = merge(local.common_tags, { Name = "${var.project}" })
}
