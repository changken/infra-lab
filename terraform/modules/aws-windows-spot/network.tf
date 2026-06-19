# ---------- Networking ----------
# 支援兩種模式：
#   1. Default VPC 模式：vpc_id = null（原有行為，不需額外設定）
#   2. 自訂 VPC 模式：  vpc_id = "vpc-xxx"（與 aws-vpc 模組搭配使用）

# ── Default VPC（僅 vpc_id 未設定時使用）──────────────────

data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.subnet_id == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.resolved_vpc_id]
  }
}

# ── 解析實際使用的 VPC / Subnet ───────────────────────────

locals {
  resolved_vpc_id    = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id
  resolved_subnet_id = var.subnet_id != null ? var.subnet_id : data.aws_subnets.default[0].ids[0]
}

# ── Security Group ─────────────────────────────────────────

resource "aws_security_group" "win2025" {
  name_prefix = "${var.name_prefix}-"
  vpc_id      = local.resolved_vpc_id

  ingress {
    description = "RDP from my IP only"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}
