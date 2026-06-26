# ---------- Networking ----------
# 支援兩種模式：
#   1. Default VPC 模式：vpc_id = null（原有行為，不需額外設定）
#   2. 自訂 VPC 模式：  vpc_id = "vpc-xxx"（與 aws-vpc 模組搭配使用）

# ── Default VPC（始終宣告，由 locals 判斷是否實際使用）─────

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ── 解析實際使用的 VPC / Subnet ───────────────────────────
# 若呼叫端傳入 vpc_id / subnet_id，優先使用；否則 fallback 到 Default VPC

locals {
  resolved_vpc_id    = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default.id
  resolved_subnet_id = var.subnet_id != null ? var.subnet_id : data.aws_subnets.default.ids[0]
}

# ── Security Group ─────────────────────────────────────────

resource "aws_security_group" "linux" {
  name_prefix = "${var.name_prefix}-"
  vpc_id      = local.resolved_vpc_id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  dynamic "ingress" {
    for_each = var.extra_ingress_ports
    content {
      description = "Custom port ${ingress.value} from my IP"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.my_ip]
    }
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
